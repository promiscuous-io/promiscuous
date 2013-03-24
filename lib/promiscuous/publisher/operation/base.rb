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
    # This method is regularly called from a worker to resend payloads that
    # never got their confirm. We get the oldest queued message, and test if
    # it's old enough to for a republish (default 10 seconds).
    # Any sort of race is okay since we would just republish, and that's okay.

    loop do
      key, time = Promiscuous::Redis.zrange(rabbitmq_staging_set_key, 0, 1, :with_scores => true).flatten
      break unless key && Time.now.to_i >= time.to_i + Promiscuous::Config.recovery_timeout

      # Refresh the score so we skip it next time we look for something to recover.
      Promiscuous::Redis.zadd(rabbitmq_staging_set_key, Time.now.to_i, key)
      payload = Promiscuous::Redis.get(key)

      Promiscuous.info "[payload recovery] #{payload}"
      new.instance_eval do
        @payload_recovery_key = key
        @amqp_key = MultiJson.load(payload)['__amqp__']
        @payload = payload
        publish_payload_in_rabbitmq_async
      end
    end
  end

  def publish_payload_in_redis
    # TODO Optimize and DRY this up
    r = @committed_read_deps
    w = @committed_write_deps

    master_node = w.first.redis_node
    operation_recovery_key = w.first.key(:pub).join('operation_recovery').to_s
    # We identify a payload with a unique key (id:id_value:current_version) to
    # avoid collisions with other updates on the same document.
    @payload_recovery_node = master_node
    @payload_recovery_key = w.first.key(:pub).join(w.first.version).to_s

    # We need to be able to recover from a redis failure. By sending the
    # payload to the slave first, we ensure that we can replay the lost
    # payloads if the primary came to fail.
    # We still need to recover the lost operations. This can be done by doing a
    # version diff from what is stored in the database and the recovered redis slave.
    # XXX TODO
    # Promiscuous::Redis.slave.set(@payload_recovery_key, @payload) if Promiscuous::Redis.slave

    # We don't care if we get raced by someone recovering our operation. It can
    # happen if we lost the lock without knowing about it.
    # The payload can be sent twice, which is okay since the subscribers
    # tolerate it.

    nodes = (w+r).map(&:redis_node).uniq
    if nodes.size == 1
      # We just have the master node. Since we are atomic, we don't need to do
      # the 2pc dance.
      master_node.multi do
        master_node.del(operation_recovery_key)
        master_node.set(@payload_recovery_key, @payload)
        master_node.zadd(rabbitmq_staging_set_key, Time.now.to_i, @payload_recovery_key)
      end
    else
      master_node.multi do
        master_node.set(@payload_recovery_key, @payload)
        master_node.zadd(rabbitmq_staging_set_key, Time.now.to_i, @payload_recovery_key)
      end

      # The payload is safe now. We can cleanup all the versions on the
      # secondary. Note that we need to clear the master node at the end,
      # as it acts as a lock on the other keys. This is important to avoid a
      # race where we would delete data that doesn't belong to the current
      # operation due to a lock loss.
      nodes.reject { |node| node == master_node }
            .each  { |node| node.del(operation_recovery_key) }
      master_node.del(operation_recovery_key)
    end
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

  def self._recover_operation(lock, model, instance_id, operation,
                              document, read_dependencies, write_dependencies)
    instance_version = write_dependencies.first.version

    if model.is_a? Promiscuous::Publisher::Model::Ephemeral
      operation = :dummy
    else
      # TODO Abstract db operations.
      # We need to query on the root model
      model = model.collection.name.singularize.camelize.constantize
      instance_scope = model.unscoped.where(:id => instance_id)
      # "lt" means less than.
      atomic_instance_scope = instance_scope.or({VERSION_FIELD.to_sym.lt => instance_version},
                                                {VERSION_FIELD => nil})
    end

    # TODO We need to use the primary database. We cannot read from a
    # secondary.

    case operation
    when :create
      instance = instance_scope.first
      unless instance
        # We re-execute the original query, and get caught by the index
        # constrain issue when clashing ids if we are racing.
        # We don't really care for any exceptions, as long as it's not a
        # networking issue (TODO).
        # Note that we are not racing with a delete, because it would have to
        # recover the create operation first.
        redo_create_operation_from(model, document, instance_version) rescue nil
        instance = instance_scope.first
      end

      # The query might not go through because the created document was invalid
      # to begin with.
      query_was_executed = !!instance
    when :update
      instance = instance_scope.where(VERSION_FIELD => instance_version).first

      unless instance
        # We must make sure to make the original query fail if we are racing with
        # it so we can send the same payload.
        atomic_instance_scope.update(VERSION_FIELD => instance_version)
        instance = instance_scope.where(VERSION_FIELD => instance_version).first
      end

      query_was_executed = true
    when :destroy
      instance = instance_scope.first

      if instance
        # Instead of redoing a destroy, we just fail the original query if the delete
        # did not get executed yet.
        atomic_instance_scope.update(VERSION_FIELD => instance_version)
        instance = instance_scope.first
      end

      query_was_executed = !instance
    end

    # If we've lost the lock, we must abort because query_was_executed might
    # not be right.
    return unless lock.still_locked?

    raise "fatal error in recovery (no instance)..." unless instance || operation != :update

    operation = :dummy unless query_was_executed
    instance ||= model.new.tap { |m| m.id = instance_id }

    # The following bootstrap a new operation to complete the operation.
    # We don't want to consider this operation as a dependency in our current
    # context, which is why the recovery context runs as a root context.
    Promiscuous.context :operation_recovery, :detached_from_parent => true do
      new(:instance => instance, :operation => operation).instance_eval do
        @committed_read_deps  = read_dependencies
        @committed_write_deps = write_dependencies

        record_timestamp
        generate_payload_and_clear_operations
        publish_payload_in_redis
        publish_payload_in_rabbitmq_async
      end
    end
  end

  def self.recover_operation(lock)
    # We happen to have acquired a never released lock.
    # The database instance is thus still prestine.
    # Three cases to consider:
    # 1) the key is not an id dependency or the payload queue stage was passed
    # 2) The write query was never executed, we must send a dummy operation
    # 3) The write query was executed, but never passed the payload queue stage
    # XXX TODO
=begin
    recovery_data = Promiscuous::Redis.get("#{lock.key}:operation_recovery")
    return nil unless recovery_data # case 1)

    Promiscuous.info "[operation recovery] #{lock.key} -> #{recovery_data}"

    to_dependency = proc do |k,v|
      k = k.split(':')[2..-1] # remove the publishers:app_name namespacing
      Promiscuous::Dependency.parse((k << v).join(':'))
    end

    recovery_data = MultiJson.load(recovery_data)
    collection         = recovery_data['collection']
    instance_id        = recovery_data['instance_id']
    operation          = recovery_data['operation'].to_sym
    document           = recovery_data['document']
    read_dependencies  = recovery_data['read_keys'].zip(recovery_data['read_versions']).map(&to_dependency)
    write_dependencies = recovery_data['write_keys'].zip(recovery_data['write_versions']).map(&to_dependency)

    model = Promiscuous::Publisher::Model.publishers[collection]
    op_klass = model.get_operation_class_for(operation)
    op_klass._recover_operation(lock, model, instance_id, operation, document, read_dependencies, write_dependencies)
  rescue Exception => e
    message = "cannot recover #{lock.key} -> #{recovery_data}"
    raise Promiscuous::Error::Recovery.new(message, e)
=end
  end

  def increment_read_and_write_dependencies
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
    operation_recovery_key = w.first.key(:pub).join('operation_recovery').to_s

    # We group all the dependencies by their respective shards
    # The master node will have the responsability to hold the recovery data.
    # We do the master node first, but it's not necessary. If we do a secondary
    # first and die right after, the data will linger around until someone
    # cleans it up, or overwrite it. This mechanism allows us to do all the
    # redis calls in parallel.
    (w+r).group_by(&:redis_node).each do |node, deps|
      r_deps = deps.select { |dep| dep.in? r }
      w_deps = deps.select { |dep| dep.in? w }
      r_keys = r_deps.map { |dep| dep.key(:pub) }
      w_keys = w_deps.map { |dep| dep.key(:pub) }

      argv = [MultiJson.dump([r_keys, w_keys])]
      # Each shard have their own recovery payload. The master recovery node
      # has the full operation recovery, and the others just have their versions.
      argv << operation_recovery_key
      if node == master_node
        # We are on the master node, which holds the recovery payload
        document = serialize_document_for_create_recovery if operation == :create
        argv << MultiJson.dump([@instance.class.promiscuous_collection_name,
                                @instance.id, operation, document, r_keys, w_keys])
      end

      # We are going to store all the versions in redis, to be able to recover.
      # We store all our increments in a transaction_id key in JSON format.
      # Note that the transaction_id is the id of the current instance.
      @@increment_script ||= Promiscuous::Redis::Script.new <<-SCRIPT
        local args = cjson.decode(ARGV[1])
        local read_keys = args[1]
        local write_keys = args[2]
        local operation_recovery_key = ARGV[2]
        local operation_recovery_payload = ARGV[3]

        local read_versions = {}
        for i, key in ipairs(read_keys) do
          redis.call('incr', key .. ':rw')
          read_versions[i] = redis.call('get', key .. ':w')
          redis.call('hset', operation_recovery_key, key, read_versions[i])
        end

        local write_versions = {}
        for i, key in ipairs(write_keys) do
          write_versions[i] = redis.call('incr', key .. ':rw')
          redis.call('set', key .. ':w', write_versions[i])
          redis.call('hset', operation_recovery_key, key, write_versions[i])
        end

        if operation_recovery_payload then
          redis.call('hset', operation_recovery_key, 'payload', operation_recovery_payload)
        end

        return { read_versions, write_versions }
      SCRIPT
      read_versions, write_versions = @@increment_script.eval(node, :argv => argv)

      r_deps.zip(read_versions).each  { |dep, version| dep.version = version.to_i }
      w_deps.zip(write_versions).each { |dep, version| dep.version = version.to_i }
    end

    @committed_read_deps  = r
    @committed_write_deps = w
    @instance_version = w.first.version
  end

  LOCK_OPTIONS = { :timeout => 10.seconds, # after 10 seconds, we give up
                   :sleep   => 0.01,       # polling every 10ms.
                   :expire  => 1.minute }  # after one minute, we are considered dead

  def self.lock_options
    LOCK_OPTIONS.merge({ :lock_set => Promiscuous::Key.new(:pub).join('lock_set').to_s })
  end

  def self.recover_locks
    # This method is regularly called from a worker to recover locks by doing a
    # locking/unlocking cycle.

    # XXX TODO
=begin
    loop do
      key, time = Promiscuous::Redis.zrange(lock_options[:lock_set], 0, 1, :with_scores => true).flatten
      break unless key && Time.now.to_i >= time.to_i + lock_options[:expire]

      mutex = Promiscuous::Redis::Mutex.new(key, lock_options)
      case mutex.lock
      when :recovered then recover_operation(mutex)
      when true       then mutex.unlock
      when false      then ;
      end
    end
=end
  end

  def locks_from_write_dependencies
    # We sort the keys to avoid deadlocks due to different lock orderings.
    write_dependencies.map do |dep|
      options = self.class.lock_options.merge(:node => dep.redis_node)
      Promiscuous::Redis::Mutex.new(dep.key(:pub).to_s, options)
    end.sort_by { |lock| lock.key }
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
        return false if Time.now - start_at > LOCK_OPTIONS[:timeout]
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
      unless best_dependency
        raise Promiscuous::Error::Dependency.new(:operation => self)
      end
      [best_dependency]
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

  def execute_persistent(&db_operation)
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
        @recovered_locks.each { |lock| self.class.recover_operation(lock) }
        auto_unlock = true
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
        return nil unless reload_instance

        # If reload_instance changed the current instance because the selector,
        # we need to unlock the old instance, lock this new instance, and
        # retry. XXX What should we do if we are going in a live lock?
        # Sleep with some jitter?
        if reload_instance_dependencies
          unlock_write_dependencies
          raise TryAgain
        end
      end
    rescue TryAgain
      retry
    end

    verify_read_dependencies
    if write_dependencies.blank?
      # TODO We don't like auto generated ids. A good solution is to do all
      # writes in a transaction, so we can know the ids at commit time.
      raise "We don't support auto generated id yet"
    end

    # We are in. We are going to commit all the pending writes in the context
    # if we are doing a transaction commit. We also commit the current write
    # operation for atomic writes without transactions.
    # We enable the recovery mechanism by having someone expiring our lock
    # if we die in the middle.
    auto_unlock = false

    # All the versions are updated and a marked as pending for publish in Redis
    # atomically in case we die before we could write the versions in the
    # database. Once incremented, concurrent queries that are reading our
    # instance will be serialized after our write, even through it may read our
    # old instance. This is a race that we tolerate.
    # XXX We also stash the document for create operations, so the recovery can
    # redo the create to avoid races when instances are getting partitioned.
    increment_read_and_write_dependencies

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
  ensure
    # In case of an exception was raised before we updated the version in
    # redis, we can unlock because we don't need recovery.
    unlock_write_dependencies if auto_unlock
  end

  # --- the following methods can be overridden by the driver to improve performance --- #

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
