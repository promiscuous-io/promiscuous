class Promiscuous::Publisher::Operation::Base
  class TryAgain < RuntimeError; end
  attr_accessor :operation, :operation_ext, :old_instance, :instance, :dependencies

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

  def on_rabbitmq_confirm
    Promiscuous::Redis.del(@amqp_recovery_key)
  end

  def publish_payload_in_rabbitmq_async
    Promiscuous::AMQP.publish(:key => @amqp_key, :payload => @payload,
                              :on_confirm => method(:on_rabbitmq_confirm))
  end

  def publish_payload_in_redis
    instance_dep = @committed_write_deps.first
    key = instance_dep.key(:pub)

    payload_recovery_key = key.join('payload_recovery').to_s

    # We use a key with the version of the instance, this way, we don't
    # collide with other updates on the same document.
    @amqp_recovery_key = key.join('amqp_recovery', instance_dep.version).to_s

    Promiscuous::Redis.multi do
      Promiscuous::Redis.del(payload_recovery_key)
      Promiscuous::Redis.set(@amqp_recovery_key, @payload)
    end
  end

  def generate_payload_and_clear_operations
    # TODO Transactions with multi writes
    raise "no multi write yet" if previous_successful_operations.select(&:write?).size > 1

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
    # TODO we should treat that link as a real read dependency and increment it,
    # otherwise it would just be a causal relationship.
    last_write_dependency = current_context.last_write_dependency
    payload[:dependencies] = {}
    payload[:dependencies][:link]  = last_write_dependency if last_write_dependency
    payload[:dependencies][:read]  = @committed_read_deps if @committed_read_deps.present?
    payload[:dependencies][:write] = @committed_write_deps

    current_context.last_write_dependency = @committed_write_deps.first
    current_context.operations.clear

    @amqp_key = payload[:__amqp__]
    @payload = payload.to_json
  end

  def self.recover_payload_for(key)
    # We happen to have acquired a never released lock.
    # The database instance is thus still prestine.
    # Three cases to consider:
    # 1) the key is not an id dependency or the payload queue stage was passed
    # 2) The write query was never executed, we must send a dummy operation
    # 3) The write query was executed, but never passed the payload queue stage

    recovery_data = Promiscuous::Redis.get("#{key}:payload_recovery")
    return nil unless recovery_data # case 1)

    to_dependency = proc do |k,v|
      k = k.split(':')[2..-1] # remove the publishers:app_name namespacing
      Promiscuous::Dependency.parse((k << v).join(':'))
    end

    recovery_data = JSON.parse(recovery_data)
    operation          = recovery_data['operation'].to_sym
    read_dependencies  = recovery_data['read_keys'].zip(recovery_data['read_versions']).map(&to_dependency)
    write_dependencies = recovery_data['write_keys'].zip(recovery_data['write_versions']).map(&to_dependency)
    instance_dep = write_dependencies.first
    raise 'assert id dependency' unless instance_dep.attribute == 'id'
    id = instance_dep.value

    # We figure out the model class from the first write dependency key name,
    # which is the same as the lock name.
    # TODO this should be abstracted since we get the collection name from an
    # abstraction to begin with.
    model = instance_dep.collection.camelize.singularize.constantize

    if operation == :destroy
      instance = fetch_instance_for_selector(model, :id => id)
      has_executed_query = !instance
    else
      # We fetch the instance from the database only if the version is matching
      # what we have in redis.
      instance = fetch_instance_for_selector(model, :id => id,
        instance_dep.version_field_name_for_recovery => instance_dep.version)
      has_executed_query = !!instance
    end

    # We send a dummy depending if the database query was executed (case 2 or 3)
    operation = has_executed_query ? operation : :dummy
    instance ||= model.new.tap { |m| m.id = id }

    # The following bootstrap a new operation to complete the operation.
    # We don't want to consider this operation as a dependency in our current
    # context, which is why the recovery context runs as a root context.
    Promiscuous.context :payload_recovery, :detached_from_parent => true do
      new(:instance => instance, :operation => operation).instance_eval do
        @committed_read_deps  = read_dependencies
        @committed_write_deps = write_dependencies
        record_timestamp
        generate_payload_and_clear_operations
        publish_payload_in_redis
        publish_payload_in_rabbitmq_async
      end
    end
  rescue Exception => e
    message = "cannot recover #{key} -> #{recovery_data}"
    raise Promiscuous::Error::Recovery.new(message, e)
  end

  def increment_read_and_write_dependencies
    # We collapse all operations, ignoring the read/write interleaving.
    # It doesn't matter since all write operations are serialized, so the first
    # write in the transaction can have all the read dependencies.
    r = read_dependencies
    w = write_dependencies
    r -= w # we don't need to do a read dependency if we are writing to it.

    # Namespacing with publishers:app_name
    r_keys = r.map { |dep| dep.key(:pub) }
    w_keys = w.map { |dep| dep.key(:pub) }

    # The recovery key must be deducted from the lock key name, which is
    # w_keys.first.
    payload_recovery_key = w_keys.first.join('payload_recovery')

    # We are going to store all the versions in redis, to be able to recover.
    # We store all our increments in a transaction_id key in JSON format.
    # Note that the transaction_id is the id of the current instance.

    # This script loading is not thread safe (touching a class variable), but
    # that's okay, because the race is harmless.
    @@increment_script_sha ||= Promiscuous::Redis.script(:load, <<-SCRIPT)
      local args = cjson.decode(ARGV[1])
      local operation = args[1]
      local read_keys = args[2]
      local write_keys = args[3]
      local payload_recovery_key = write_keys[1] .. ':payload_recovery'

      local read_versions = {}
      for i, key in ipairs(read_keys) do
        redis.call('incr', key .. ':rw')
        read_versions[i] = redis.call('get', key .. ':w')
      end

      local write_versions = {}
      for i, key in ipairs(write_keys) do
        write_versions[i] = redis.call('incr', key .. ':rw')
        redis.call('set', key .. ':w', write_versions[i])
      end

      redis.call('set', payload_recovery_key, cjson.encode({
        read_keys=read_keys, read_versions=read_versions,
        write_keys=write_keys, write_versions=write_versions,
        operation=operation}))

      return { read_versions, write_versions }
    SCRIPT

    keys_to_touch = (r_keys + w_keys).map { |key| [key.join('rw'), key.join('w')] }.flatten
    keys_to_touch << payload_recovery_key

    # Note that this script is run in a Redis transaction, which is something
    # we rely on.
    read_versions, write_versions = Promiscuous::Redis.evalsha(@@increment_script_sha,
                                      :keys => keys_to_touch.map(&:to_s),
                                      :argv => [[operation,r_keys,w_keys].to_json])

    r.zip(read_versions).map  { |dep, version| dep.version = version.to_i }
    w.zip(write_versions).map { |dep, version| dep.version = version.to_i }
    @committed_read_deps  = r
    @committed_write_deps = w
  end

  LOCK_OPTIONS = { :timeout => 10.seconds, # after 10 seconds, we give up
                   :sleep   => 0.01,       # polling every 10ms.
                   :expire  => 1.minute }  # after one minute, we are considered dead

  def lock_write_dependencies
    # returns true if we could get all the locks, false otherwise

    # We sort the keys to avoid deadlocks due to different lock orderings.
    locks = write_dependencies.map { |dep| dep.key(:pub).to_s }.sort
              .map { |key| Promiscuous::Redis::Mutex.new(key, LOCK_OPTIONS) }

    start_at = Time.now
    @recovered_locks = []

    # We acquire all the locks in order, and unlock everything if one come
    # to fail. lock/unlock return true/false when they succeed/fail
    # TODO recover if we expire a lock
    locks.reduce(->{ @locks = locks; true }) do |chain, l|
      lambda do
        return false if Time.now - start_at > LOCK_OPTIONS[:timeout]
        case l.lock
        # Note that we do not unlock the recovered lock if the chain fails
        when :recovered then @recovered_locks << l.key; chain.call
        when true       then chain.call or (l.unlock; false)
        when false      then @unavailable_lock = l.key; false
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
    @read_dependencies ||= previous_successful_operations.select(&:read?)
                             .map(&:instance_dependencies).flatten.uniq
  end

  def write_dependencies
    # The cache is cleared when we call reload_instance_dependencies
    @write_dependencies ||= previous_successful_operations.select(&:write?)
                              .map(&:instance_dependencies).flatten.uniq
  end

  def reload_instance
    @instance = without_promiscuous { fetch_instance }
  end

  def perform_db_operation_with_no_exceptions(&db_operation)
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
        raise Promiscuous::Error::LockUnavailable.new(@unavailable_lock)
      end

      if @recovered_locks.present?
        # When recovering locks, if we fail, we must not release the lock again
        # to allow another one to do the recovery.
        auto_unlock = false
        @recovered_locks.each { |key| self.class.recover_payload_for(key) }
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

        # We are now in the possession of an instance that matches the user's
        # selector We need to make sure the db_operation will operate on it,
        # instead of the original selector.
        # TODO XXX What happens with a transaction commit?
        use_id_selector
      end
    rescue TryAgain
      retry
    end

    if write_dependencies.blank?
      # TODO We don't like auto generated ids. A good solution is to do all
      # writes in a transaction, so we can know the ids at commit time.
      raise "auto generated id issue"
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
    #
    # This method is implemented in each driver.
    stash_write_dependencies_in_write_query unless operation == :destroy

    # Perform the actual database query (single write or transaction commit).
    # If successful, the result goes in @result, otherwise, @exception contains
    # the thrown exception.
    perform_db_operation_with_no_exceptions(&db_operation)

    # We take a timestamp right after the write is performed because latency
    # measurements are performed on the subscriber.
    record_timestamp

    # The underlying driver should implement some sort of find and modify
    # operation in the previous write query to avoid this extra read query.
    # If reload_instance_after_update raise an exception, we let it bubble up,
    # and we'll trigger the recovery mechanism.
    reload_instance_after_update if operation == :update && !failed?
    generate_payload_and_clear_operations

    # As soon as we unlock the locks, the rescuer will not be able to assume
    # that the database instance is still pristine, and so we need to stash the
    # payload in redis. If redis dies, we don't care because it can be
    # reconstructed. Subscribers can see "compressed" updates.
    publish_payload_in_redis

    unless unlock_write_dependencies
      # TODO Our lock got expired by someone. What are we supposed to do?
      # This should never happen based on the timeouts we have.
      raise 'oops'
    end

    publish_payload_in_rabbitmq_async

    # If we die from this point on, a recovery worker can republish our payload
    # since we queued it in Redis.
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

  def self.fetch_instance_for_selector(model, selector)
    model.where(selector).first
  end

  def fetch_instance
    # This method is overridden to use the original query selector.
    # Not used in the case of a create operation.
    # Should return nil if the instance is not found.
    @instance
  end

  def use_id_selector
    # to be overridden to use the {:id => @instance.id} selector for the
    # db_operation
  end

  def stash_write_dependencies_in_write_query
    # This is implemented by the driver to something similar to:
    # @committed_write_deps.each do |dep|
    #  @instance.__send__("#{dep.version_field_name_for_recovery}=", dep.version)
    # end
  end

  def reload_instance_after_update
    # @old_instance is used for better error messages.
    @old_instance, @instance = @instance, fetch_instance
  rescue Exception => e
    # XXX We are writing to the log file a stale instance, not great for a log replay.
    raise Promiscuous::Error::Publisher.new(e, :instance => @instance)
  end
end
