class Promiscuous::Publisher::Operation::Base
  class TryAgain < RuntimeError; end
  VERSION_FIELD = '_pv'

  attr_accessor :operation, :operation_ext, :instance, :selector_keys

  def initialize(options={})
    # XXX instance is not always an instance, it can be a selector
    # representation.
    @instance      = options[:instance]
    @operation     = options[:operation]
    @operation_ext = options[:operation_ext]
    @multi         = options[:multi]
  end

  def read?
    operation == :read
  end

  def write?
    !read?
  end

  def multi?
    !!@multi
  end

  def single?
    !@multi
  end

  def persists?
    # TODO For writes in transactions, it should be false
    write?
  end

  def failed?
    !!@exception
  end

  def current_context
    @current_context ||= Promiscuous::Publisher::Context.current
  end

  def record_timestamp
    # Records the number of milliseconds since epoch, which we use send sending
    # the payload over. It's good for latency measurements.
    time = Time.now
    @timestamp = time.to_i * 1000 + time.usec / 1000
  end

  def self.rabbitmq_staging_set_key
    Promiscuous::Key.new(:pub).join('rabbitmq_staging').to_s
  end

  delegate :rabbitmq_staging_set_key, :to => self

  def on_rabbitmq_confirm
    # These requests could be parallelized, rabbitmq persisted the operation.
    # XXX TODO
    # Promiscuous::Redis.slave.del(@payload_recovery_key) if Promiscuous::Redis.slave

    @payload_recovery_node.multi do
      @payload_recovery_node.del(@payload_recovery_key)
      @payload_recovery_node.zrem(rabbitmq_staging_set_key, @payload_recovery_key)
    end
  end

  def publish_payload_in_rabbitmq_async
    Promiscuous::AMQP.publish(:key => @amqp_key, :payload => @payload,
                              :on_confirm => method(:on_rabbitmq_confirm))
  end

  def self.recover_payloads_for_rabbitmq
    return unless Promiscuous::Redis.master
    # This method is regularly called from a worker to resend payloads that
    # never got their confirm. We get the oldest queued message, and test if
    # it's old enough to for a republish (default 10 seconds).
    # Any sort of race is okay since we would just republish, and that's okay.

    Promiscuous::Redis.master.nodes.each do |node|
      loop do
        key, time = node.zrange(rabbitmq_staging_set_key, 0, 1, :with_scores => true).flatten
        break unless key && Time.now.to_i >= time.to_i + Promiscuous::Config.recovery_timeout

        # Refresh the score so we skip it next time we look for something to recover.
        node.zadd(rabbitmq_staging_set_key, Time.now.to_i, key)
        payload = node.get(key)

        Promiscuous.info "[payload recovery] #{payload}"
        new.instance_eval do
          @payload_recovery_node = node
          @payload_recovery_key = key
          @amqp_key = MultiJson.load(payload)['__amqp__']
          @payload = payload
          publish_payload_in_rabbitmq_async
        end
      end
    end
  end

  def publish_payload_in_redis
    # TODO Optimize and DRY this up
    r = @committed_read_deps
    w = @committed_write_deps

    master_node = w.first.redis_node

    # We identify a payload with a unique key (id:id_value:current_version:payload_recovery)
    # to avoid collisions with other updates on the same document.
    @payload_recovery_node = master_node
    @payload_recovery_key = w.first.key(:pub).join(w.first.version, 'payload_recovery').to_s

    # We need to be able to recover from a redis failure. By sending the
    # payload to the slave first, we ensure that we can replay the lost
    # payloads if the master came to fail.
    # We still need to recover the lost operations. This can be done by doing a
    # version diff from what is stored in the database and the recovered redis slave.
    # XXX TODO
    # Promiscuous::Redis.slave.set(@payload_recovery_key, @payload) if Promiscuous::Redis.slave

    # We don't care if we get raced by someone recovering our operation. It can
    # happen if we lost the lock without knowing about it.
    # The payload can be sent twice, which is okay since the subscribers
    # tolerate it.
    master_operation_recovery_key = w.first.key(:pub).join('operation_recovery').to_s
    master_node.multi do
      master_node.set(@payload_recovery_key, @payload)
      master_node.zadd(rabbitmq_staging_set_key, Time.now.to_i, @payload_recovery_key)
      master_node.del(master_operation_recovery_key)
    end

    # The payload is safe now. We can cleanup all the versions on the
    # secondary. There are no harmful races that can happen since the
    # secondary_operation_recovery_key is unique to the operation.
    # XXX The caveat is that if we die here, the
    # secondary_operation_recovery_key will never be cleaned up.
    secondary_operation_recovery_key = w.first.key(:pub).join(w.first.version, 'operation_recovery').to_s
    (w+r).map(&:redis_node).uniq
      .reject { |node| node == master_node }
      .each   { |node| node.del(secondary_operation_recovery_key) }
  end

  def generate_payload_and_clear_operations
    # TODO Transactions with multi writes
    raise "We don't support multi writes yet" if previous_successful_operations.select(&:write?).size > 1
    raise "The instance is gone, or there is a version mismatch" unless @instance

    payload = @instance.promiscuous.payload(:with_attributes => operation.in?([:create, :update]))
    payload[:context] = current_context.name
    payload[:timestamp] = @timestamp

    # If the db operation has failed, so we publish a dummy operation on the
    # failed instance. It's better than using the Dummy polisher class
    # because a subscriber can choose not to receive any of these messages.
    payload[:operation] = self.failed? ? :dummy : operation

    # We need to consider the last write operation as an implicit read
    # dependency. This is why we don't need to consider the read dependencies
    # happening before a first write when publishing the second write in a
    # context.
    payload[:dependencies] = {}
    payload[:dependencies][:read]  = @committed_read_deps if @committed_read_deps.present?
    payload[:dependencies][:write] = @committed_write_deps

    current_context.last_write_dependency = @committed_write_deps.first
    current_context.operations.clear

    @amqp_key = payload[:__amqp__]
    @payload = MultiJson.dump(payload)
  end

  def self.recover_operation_from_lock(lock)
    # We happen to have acquired a never released lock.
    # The database instance is thus still prestine.

    master_node = lock.node
    recovery_data = master_node.hgetall("#{lock.key}:operation_recovery")

    return unless recovery_data.present?

    Promiscuous.info "[operation recovery] #{lock.key} -> #{recovery_data}"

    collection, instance_id, operation,
      document, read_dependencies, write_dependencies = *MultiJson.load(recovery_data['payload'])

    operation = operation.to_sym
    read_dependencies.map!  { |k| Promiscuous::Dependency.parse(k.to_s, :type => :read) }
    write_dependencies.map! { |k| Promiscuous::Dependency.parse(k.to_s, :type => :write) }

    model = Promiscuous::Publisher::Model.publishers[collection]

    if model.is_a? Promiscuous::Publisher::Model::Ephemeral
      operation = :dummy
    else
      # TODO Abstract db operations.
      # We need to query on the root model
      model = model.collection.name.singularize.camelize.constantize
    end

    op_klass = model.get_operation_class_for(operation)
    op = op_klass.recover_operation(model, instance_id, document)
    op.operation = operation

    Promiscuous.context :operation_recovery, :detached_from_parent => true do
      op.instance_eval do
        @read_dependencies  = read_dependencies
        @write_dependencies = write_dependencies
        @locks = [lock]
        execute_persistent_locked { recover_db_operation }
      end
    end

  ### TODO DEBUG CODE - REMOVE AT SOME POINT ###
  rescue Redis::CommandError => e
    key_type = nil
    begin
      require 'base64'
      key_type = master_node.type("#{lock.key}:operation_recovery")
      recovery_data = master_node.dump("#{lock.key}:operation_recovery") unless recovery_data
      recovery_data = Base64.strict_encode64(recovery_data)
    rescue Exception
    end
    message = "cannot recover #{lock.key}, failed to fetch raw recovery data"
    message = "cannot recover #{lock.key}, key_type: #{key_type}, raw recovery data: #{recovery_data}" if recovery_data
    raise Promiscuous::Error::Recovery.new(message, e)
  ### TODO DEBUG CODE - REMOVE AT SOME POINT ###

  rescue Exception => e
    message = "cannot recover #{lock.key}, failed to fetch recovery data"
    message = "cannot recover #{lock.key}, recovery data: #{recovery_data}" if recovery_data
    raise Promiscuous::Error::Recovery.new(message, e)
  end

  def increment_read_and_write_dependencies(read_dependencies, write_dependencies)
    # We collapse all operations, ignoring the read/write interleaving.
    # It doesn't matter since all write operations are serialized, so the first
    # write in the transaction can have all the read dependencies.
    r = read_dependencies
    w = write_dependencies

    # We don't need to do a read dependency if we are writing to it, so we
    # prune them. The subscriber assumes the pruning (i.e. the intersection of
    # r and w is empty) when it calculates the happens before relationships.
    r -= w

    master_node = w.first.redis_node
    operation_recovery_key = w.first

    # We group all the dependencies by their respective shards
    # The master node will have the responsability to hold the recovery data.
    # We do the master node first. The seconaries can be done in parallel.
    (w+r).group_by(&:redis_node).each do |node, deps|
      r_deps = deps.select { |dep| dep.in? r }
      w_deps = deps.select { |dep| dep.in? w }

      increment_redis = lambda {
        argv = []
        argv << Promiscuous::Key.new(:pub) # key prefixes
        argv << MultiJson.dump([r_deps, w_deps])

        # Each shard have their own recovery payload. The master recovery node
        # has the full operation recovery, and the others just have their versions.
        # Note that the operation_recovery_key on the secondaries have the current
        # version of the instance appended to them. It's easier to cleanup when
        # locks get lost.
        argv << operation_recovery_key.as_json
        if node == master_node
          # We are on the master node, which holds the recovery payload
          document = serialize_document_for_create_recovery if operation == :create
          argv << MultiJson.dump([@instance.class.promiscuous_collection_name,
                                  @instance.id, operation, document, r, w])
        end

        # FIXME If the lock is lost, we need to backoff

        # We are going to store all the versions in redis, to be able to recover.
        # We store all our increments in a transaction_id key in JSON format.
        # Note that the transaction_id is the id of the current instance.
        @@increment_script ||= Promiscuous::Redis::Script.new <<-SCRIPT
          local prefix = ARGV[1] .. ':'
          local deps = cjson.decode(ARGV[2])
          local read_deps = deps[1]
          local write_deps = deps[2]
          local operation_recovery_key = prefix .. ARGV[3] .. ':operation_recovery'
          local operation_recovery_payload = ARGV[4]

          if redis.call('exists', '#{Promiscuous::Publisher::Bootstrap::KEY}') == 1 and #read_deps > 0 then
            return -1
          end

          local read_versions = {}
          local write_versions = {}

          if redis.call('exists', operation_recovery_key) == 1 then
            for i, dep in ipairs(read_deps) do
              read_versions[i] = redis.call('hget', operation_recovery_key, dep)
              if not read_versions[i] then
                return redis.error_reply('Failed to read dependency ' .. dep .. ' during recovery')
              end
            end

            for i, dep in ipairs(write_deps) do
              write_versions[i] = redis.call('hget', operation_recovery_key, dep)
              if not write_versions[i] then
                return redis.error_reply('Failed to read dependency ' .. dep .. ' during recovery')
              end
            end

            return { read_versions, write_versions }
          end

          for i, dep in ipairs(read_deps) do
            local key = prefix .. dep
            redis.call('incr', key .. ':rw')
            read_versions[i] = redis.call('get', key .. ':w')
            redis.call('hset', operation_recovery_key, dep, read_versions[i] or 0)
          end

          for i, dep in ipairs(write_deps) do
            local key = prefix .. dep
            write_versions[i] = redis.call('incr', key .. ':rw')
            redis.call('set', key .. ':w', write_versions[i])
            redis.call('hset', operation_recovery_key, dep, write_versions[i] or 0)
          end

          if operation_recovery_payload then
            redis.call('hset', operation_recovery_key, 'payload', operation_recovery_payload)
          end

          return { read_versions, write_versions }
        SCRIPT
        @@increment_script.eval(node, :argv => argv)
      }
      result = increment_redis.call
      if result == -1 # Bootstrapping
        w_deps += r_deps; r_deps = []
        w += r; r = []

        result = increment_redis.call
      end

      read_versions, write_versions = result

      r_deps.zip(read_versions).each  { |dep, version| dep.version = version.to_i }
      w_deps.zip(write_versions).each { |dep, version| dep.version = version.to_i }
    end

    @committed_read_deps  = r
    @committed_write_deps = w
    @instance_version = w.first.version
  end

  def self.lock_options
    @@lock_options ||= {
      :timeout  => 10.seconds,   # after 10 seconds, we give up so we don't queue requests
      :sleep    => 0.01.seconds, # polling every 10ms.
      :expire   => 1.minute,     # after one minute, we are considered dead
      :lock_set => Promiscuous::Key.new(:pub).join('lock_set').to_s
    }
  end
  delegate :lock_options, :to => self

  def self.recover_locks
    return unless Promiscuous::Redis.master
    # This method is regularly called from a worker to recover locks by doing a
    # locking/unlocking cycle.

    Promiscuous::Redis.master.nodes.each do |node|
      loop do
        key, time = node.zrange(lock_options[:lock_set], 0, 1, :with_scores => true).flatten
        break unless key && Time.now.to_i >= time.to_i + lock_options[:expire]

        mutex = Promiscuous::Redis::Mutex.new(key, lock_options.merge(:node => node))
        case mutex.lock
        when :recovered then recover_operation_from_lock(mutex); mutex.unlock
        when true       then mutex.unlock
        when false      then ;
        end
      end
    end
  end

  def locks_from_write_dependencies
    # XXX TODO Support multi row writes
    instance_dep = write_dependencies.first
    return [] unless instance_dep
    options = lock_options.merge(:node => instance_dep.redis_node)
    [Promiscuous::Redis::Mutex.new(instance_dep.key(:pub).to_s, options)]
  end

  def lock_write_dependencies
    # returns true if we could get all the locks, false otherwise

    start_at = Time.now
    @recovered_locks = []

    # We acquire all the locks in order, and unlock everything if one come
    # to fail. lock/unlock return true/false when they succeed/fail
    locks = locks_from_write_dependencies
    locks.reduce(->{ @locks = locks; true }) do |chain, l|
      lambda do
        if Time.now - start_at > lock_options[:timeout]
          @unavailable_lock = l
          return false
        end

        case l.lock
          # Note that we do not unlock the recovered lock if the chain fails
        when :recovered then @recovered_locks << l; chain.call
        when true       then chain.call or (l.unlock; false)
        when false      then @unavailable_lock = l; false
        end
      end
    end.call
  end

  def unlock_write_dependencies
    # returns true if we could unlock all the locks, false otherwise
    return true if @locks.blank?
    @locks.reduce(true) { |result, l| l.unlock && result }.tap { @locks = nil }
  end

  def _reload_instance_dependencies
    if read?
      # We want to use the smallest subset that we can depend on when doing
      # reads. tracked_dependencies comes sorted from the smallest subset to
      # the largest. For maximum performance on the subscriber side, we thus
      # pick the first one. In most cases, it should resolve to the id
      # dependency.
      best_dependency = @instance.promiscuous.tracked_dependencies.first
      if Promiscuous::Config.strict_multi_read
        unless best_dependency
          raise Promiscuous::Error::Dependency.new(:operation => self)
        end
      end
      [best_dependency].compact
    else
      # Note that tracked_dependencies will not return the id dependency if it
      # doesn't exist which can only happen for create operations and auto
      # generated ids. Be aware that with auto generated id, create operation
      # might not provide the id dependency.
      @instance.promiscuous.tracked_dependencies
    end
  end

  def reload_instance_dependencies
    # Returns true when the dependencies changed, false otherwise
    @write_dependencies = nil
    old = @instance_dependencies
    @instance_dependencies = _reload_instance_dependencies
    old != @instance_dependencies
  end

  def instance_dependencies
    reload_instance_dependencies unless @instance_dependencies
    @instance_dependencies
  end

  def previous_successful_operations
    current_context.operations.reject(&:failed?)
  end

  def read_dependencies
    # We memoize the read dependencies not just for performance, but also
    # because we store the versions once incremented in these.
    return @read_dependencies if @read_dependencies
    read_dependencies = previous_successful_operations.select(&:read?)
                             .map(&:instance_dependencies).flatten

    # We implicitly have a read dependency on the latest write.
    if current_context.last_write_dependency
      current_context.last_write_dependency.version = nil
      read_dependencies << current_context.last_write_dependency
    end

    @read_dependencies = read_dependencies.uniq
  end
  alias verify_read_dependencies read_dependencies

  def write_dependencies
    # The cache is cleared when we call reload_instance_dependencies
    @write_dependencies ||= previous_successful_operations.select(&:write?)
                              .map(&:instance_dependencies).flatten.uniq
  end

  def reload_instance
    @instance = without_promiscuous { fetch_instance }
  end

  def perform_db_operation_with_no_exceptions(&db_operation)
    going_to_execute_db_operation
    @result = db_operation.call(self)
  rescue Exception => e
    @exception = e
  end

  def lock_instance_for_execute_persistent
    current_context.add_operation(self)

    # Note: At first, @instance can be a representation of a selector, to
    # become a real model instance once we get to fetch it from the db with
    # reload_instance to lock an instance that matches the selector.
    # This is a good thing because we allow the underlying driver to hook from
    # the model interface to the driver interface easily.
    auto_unlock = true

    begin
      unless lock_write_dependencies
        raise Promiscuous::Error::LockUnavailable.new(@unavailable_lock.key)
      end

      if @recovered_locks.present?
        # When recovering locks, if we fail, we must not release the lock again
        # to allow another one to do the recovery.
        auto_unlock = false
        @recovered_locks.each { |lock| self.class.recover_operation_from_lock(lock); lock.unlock }
        auto_unlock = true
        raise TryAgain
      end

      if operation != :create
        # We need to lock and update all the dependencies before any other
        # readers can see our write through any one of our tracked attributes.

        # We want to reload the instance to make sure we have all the locked
        # dependencies that we need. It's a query we cannot avoid when we have
        # tracked dependencies. There is a bit of room for optimization.
        # If the selector doesn't fetch any instance, the query has no effect
        # so we can bypass it as if nothing happened.  If reload_instance
        # raises an exception, it's okay to let it bubble up since we haven't
        # touch anything yet except for the locks (which will be unlocked on
        # the way out)
        return false unless reload_instance

        # If reload_instance changed the current instance because the selector,
        # we need to unlock the old instance, lock this new instance, and
        # retry. XXX What should we do if we are going in a live lock?
        # Sleep with some jitter?
        if reload_instance_dependencies
          raise TryAgain
        end
      end
    rescue TryAgain
      unlock_write_dependencies if auto_unlock
      retry
    end

    verify_read_dependencies
    if write_dependencies.blank?
      # TODO We don't like auto generated ids. A good solution is to do all
      # writes in a transaction, so we can know the ids at commit time.
      raise "We don't support auto generated id yet"
    end

    # We are now in the possession of an instance that matches the original
    # selector, we can proceed.
    auto_unlock = false
    true
  ensure
    # In case of an exception was raised before we updated the version in
    # redis, we can unlock because we don't need recovery.
    unlock_write_dependencies if auto_unlock
  end

  def execute_persistent_locked(&db_operation)
    # We are going to commit all the pending writes in the context if we are
    # doing a transaction commit. We also commit the current write operation for
    # atomic writes without transactions.  We enable the recovery mechanism by
    # having someone expiring our lock if we die in the middle.

    # All the versions are updated and a marked as pending for publish in Redis
    # atomically in case we die before we could write the versions in the
    # database. Once incremented, concurrent queries that are reading our
    # instance will be serialized after our write, even through it may read our
    # old instance. This is a race that we tolerate.
    # XXX We also stash the document for create operations, so the recovery can
    # redo the create to avoid races when instances are getting partitioned.
    increment_read_and_write_dependencies(read_dependencies, write_dependencies)

    # From this point, if we die, the one expiring our write locks must finish
    # the publish, either by sending a dummy, or by sending the real instance.
    # We could have die before or after the database query.

    # We save the versions in the database, as it is our source of truth.
    # This allow a reconstruction of redis in the face of failures.
    # We would also need to send a special message to the subscribers to reset
    # their read counters to the last write version since we would not be able
    # to restore the read counters (and we don't want to store them because
    # this would dramatically augment our footprint on the db).
    #
    # If we are doing a destroy operation, and redis dies right after, and
    # we happen to lost contact with rabbitmq, recovery is going to be complex:
    # we would need to do a diff from the dummy subscriber to see what
    # documents are missing on our side to be able to resend the destroy
    # message.

    case operation
    when :create
      stash_version_in_write_query
    when :update
      stash_version_in_write_query
      # We are now in the possession of an instance that matches the original
      # selector. We need to make sure the db_operation will operate on it,
      # instead of the original selector.
      use_id_selector(:use_atomic_version_selector => true)
      # We need to use an atomic versioned selector to make sure that
      # if we lose the lock for a long period of time, we don't mess up
      # with other people's updates. Also we make sure that the recovery
      # mechanism is not racing with us.
    when :destroy
      use_id_selector(:use_atomic_version_selector => true)
    end

    # Perform the actual database query (single write or transaction commit).
    # If successful, the result goes in @result, otherwise, @exception contains
    # the thrown exception.
    perform_db_operation_with_no_exceptions(&db_operation)

    # We take a timestamp right after the write is performed because latency
    # measurements are performed on the subscriber.
    record_timestamp

    if operation == :update && !failed?
      # The underlying driver should implement some sort of find and modify
      # operation in the previous write query to avoid this extra read query.
      # If reload_instance raise an exception, we let it bubble up,
      # and we'll trigger the recovery mechanism.
      use_id_selector
      reload_instance
    end

    unless @locks.first.still_locked?
      # We lost the lock, let the recovery mechanism do its thing.
      # This is a code optimization to avoid checking if the db operation
      # succeeded or not because of the db operation race during recovery.
      raise Promiscuous::Error::LostLock.new(@locks.first.key)
    end

    generate_payload_and_clear_operations

    # As soon as we unlock the locks, the rescuer will not be able to assume
    # that the database instance is still pristine, and so we need to stash the
    # payload in redis. If redis dies, we don't care because it can be
    # reconstructed. Subscribers can see "compressed" updates.
    publish_payload_in_redis

    # TODO Performance: merge these 3 redis operations to speed things up.
    unlock_write_dependencies

    # If we die from this point on, a recovery worker can republish our payload
    # since we queued it in Redis.

    # We don't care if we lost the lock and got recovered, subscribers are
    # immune to duplicate messages.
    publish_payload_in_rabbitmq_async
  end

  # --- the following methods can be overridden by the driver  --- #

  def execute_persistent(&db_operation)
    return nil unless lock_instance_for_execute_persistent
    execute_persistent_locked(&db_operation)
  end

  def execute_non_persistent(&db_operation)
    # We are getting here in the following cases:
    # * read: we fetch the instance. It's the driver's job to cache the
    #       raw instance and return it during db_operation.
    # * multi read: nothing to do, we'll keep our current selector, sadly
    # * write in a transaction: TODO

    if single?
      # If the query misses, we don't bother
      return nil unless reload_instance
      use_id_selector
    end

    # We don't do any reload_instance_dependencies at this point (and thus we
    # won't raise an exception on a multi read that we cannot track).
    # We'll wait until the commit, and hopefully with tainting, we'll be able to
    # tell if we should depend the multi read operation in question.
    perform_db_operation_with_no_exceptions(&db_operation)
    # If the db_operation raises, we don't consider this failed operation when
    # committing the next persistent write by omitting the operation in the
    # context.
    current_context.add_operation(self) unless failed?
  end

  def execute(&db_operation)
    # execute returns the result of the db_operation to perform
    db_operation ||= proc {}
    return db_operation.call if Promiscuous.disabled

    unless current_context
      raise Promiscuous::Error::MissingContext if write?
      return db_operation.call # Don't care for a read
    end

    self.persists? ? execute_persistent(&db_operation) :
                     execute_non_persistent(&db_operation)

    @exception ? (raise @exception) : @result
  end

  def fetch_instance
    # This method is overridden to use the original query selector.
    # Should return nil if the instance is not found.
    @instance
  end

  def serialize_document_for_create_recovery
    # Overridden to be able to redo the create during recovery.
    nil
  end

  def self.recover_operation(model, instance_id, document)
    # Overriden to reconstruct the operation. If the database is read, only the
    # primary must be used.
    new(:instance => model.new { |instance| instance.id = instance_id })
  end

  def recover_db_operation
    # Overriden to reexecute the db operation during recovery (or make sure that
    # it will never succeed).
  end

  def use_id_selector(options={})
    # Overridden to use the {:id => @instance.id} selector.
    # if use_atomic_version_selector is passed, the driver must
    # add the VERSION_FIELD selector if present in original instance.
  end

  def use_versioned_selector
    # Overridden to use the {VERSION_FIELD => @instance[VERSION_FIELD]} selector.
  end

  def stash_version_in_write_query
    # Overridden to update the query to set 'instance.VERSION_FIELD = @instance_version'
  end

  def going_to_execute_db_operation
    # Test hook
  end
end
