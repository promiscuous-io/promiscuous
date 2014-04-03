class Promiscuous::Publisher::Operation::Base
  mattr_accessor :recovery_mechanisms
  self.recovery_mechanisms = []

  def self.register_recovery_mechanism(method_name=nil, &block)
    self.recovery_mechanisms << (block || method(method_name))
  end

  def self.run_recovery_mechanisms
    self.recovery_mechanisms.each(&:call)
  end

  attr_accessor :operation

  def initialize(options={})
    @operation = options[:operation]
  end

  def recovering?
    !!@recovery_data
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
    Promiscuous::AMQP.publish(:key => Promiscuous::Config.app, :payload => @payload,
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

        # It's possible that the payload is nil as the message could be
        # recovered by another worker
        if payload
          Promiscuous.info "[payload recovery] #{payload}"
          new.instance_eval do
            @payload_recovery_node = node
            @payload_recovery_key = key
            @payload = payload
            @recovery = true
            publish_payload_in_rabbitmq_async
          end
        end
      end
    end
  end
  register_recovery_mechanism :recover_payloads_for_rabbitmq

  def publish_payload_in_redis
    # TODO Optimize and DRY this up
    w = @committed_write_deps

    # We identify a payload with a unique key (id:id_value:current_version:payload_recovery)
    # to avoid collisions with other updates on the same document.
    master_node = @op_lock.node
    @payload_recovery_node = master_node
    @payload_recovery_key = Promiscuous::Key.new(:pub).join('payload_recovery', @op_lock.token).to_s

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
    operation_recovery_key = "#{@op_lock.key}:operation_recovery"
    versions_recovery_key = "#{operation_recovery_key}:versions"

    master_node.multi do
      master_node.set(@payload_recovery_key, @payload)
      master_node.zadd(rabbitmq_staging_set_key, Time.now.to_i, @payload_recovery_key)
      master_node.del(operation_recovery_key)
      master_node.del(versions_recovery_key)
    end

    # The payload is safe now. We can cleanup all the versions on the
    # secondary. There are no harmful races that can happen since the
    # secondary_operation_recovery_key is unique to the operation.
    # XXX The caveat is that if we die here, the
    # secondary_operation_recovery_key will never be cleaned up.
    w.map(&:redis_node).uniq
      .reject { |node| node == master_node }
      .each   { |node| node.del(versions_recovery_key) }
  end

  def payload_for(instance)
    options = { :with_attributes => self.operation.in?([:create, :update]) }
    instance.promiscuous.payload(options).tap do |payload|
      payload[:operation] = self.operation
    end
  end

  def generate_payload
    payload = {}
    payload[:operations] = operation_payloads
    payload[:app] = Promiscuous::Config.app
    payload[:current_user_id] = Promiscuous.context.current_user.id if Promiscuous.context.current_user
    payload[:timestamp] = @timestamp
    payload[:generation] = Promiscuous::Config.generation
    payload[:host] = Socket.gethostname
    payload[:recovered_operation] = true if recovering?
    payload[:dependencies] = {}
    payload[:dependencies][:write] = @committed_write_deps

    @payload = MultiJson.dump(payload)
  end

  def self.recover_operation_from_lock(lock)
    # We happen to have acquired a never released lock.
    # The database instance is thus still pristine.

    master_node = lock.node
    recovery_data = master_node.get("#{lock.key}:operation_recovery")

    unless recovery_data.present?
      lock.unlock
      return
    end

    Promiscuous.info "[operation recovery] #{lock.key} -> #{recovery_data}"

    op_klass, operation, write_dependencies, recovery_arguments = *MultiJson.load(recovery_data)

    operation = operation.to_sym
    write_dependencies.map! { |k| Promiscuous::Dependency.parse(k.to_s, :type => :write) }

    begin
      op = op_klass.constantize.recover_operation(*recovery_arguments)
    rescue NameError
      raise "invalid recover operation class: #{op_klass}"
    end

    Thread.new do
      # We run the recovery in another thread to ensure that we get a new
      # database connection to avoid tampering with the current state of the
      # connection, which can be in an open transaction.
      # Thankfully, we are not in a fast path.
      # Note that any exceptions will be passed through the thread join() method.
      op.instance_eval do
        @operation = operation
        @write_dependencies = write_dependencies
        @op_lock = lock
        @recovery_data = recovery_data

        query = Promiscuous::Publisher::Operation::ProxyForQuery.new(self) { recover_db_operation }
        self.execute_instrumented(query)
        query.result
      end
    end.join

  rescue Exception => e
    message = "cannot recover #{lock.key}, failed to fetch recovery data"
    message = "cannot recover #{lock.key}, recovery data: #{recovery_data}" if recovery_data
    raise Promiscuous::Error::Recovery.new(message, e)
  end

  def increment_dependencies
    # We collapse all operations, ignoring the read/write interleaving.
    # It doesn't matter since all write operations are serialized, so the first
    # write in the transaction can have all the read dependencies.
    w = write_dependencies

    master_node = @op_lock.node
    operation_recovery_key = "#{@op_lock.key}:operation_recovery"

    # We group all the dependencies by their respective shards
    # The master node will have the responsibility to hold the recovery data.
    # We do the master node first. The secondaries can be done in parallel.
    @committed_write_deps = []

    # We need to do the increments always in the same node order, otherwise.
    # the subscriber can deadlock. But we must always put the recovery payload
    # on the master before touching anything.
    nodes_deps = w.group_by(&:redis_node)
                  .sort_by { |node, deps| -Promiscuous::Redis.master.nodes.index(node) }
    if nodes_deps.first[0] != master_node
      nodes_deps = [[master_node, []]] + nodes_deps
    end

    nodes_deps.each do |node, deps|
      argv = []
      argv << Promiscuous::Key.new(:pub) # key prefixes
      argv << operation_recovery_key

      # Each shard have their own recovery payload. The master recovery node
      # has the full operation recovery, and the others just have their versions.
      # Note that the operation_recovery_key on the secondaries have the current
      # version of the instance appended to them. It's easier to cleanup when
      # locks get lost.
      if node == master_node && !self.recovering?
        # We are on the master node, which holds the recovery payload
        argv << MultiJson.dump([self.class.name, operation, w, self.recovery_payload])
      end

      # FIXME If the lock is lost, we need to backoff

      # We are going to store all the versions in redis, to be able to recover.
      # We store all our increments in a transaction_id key in JSON format.
      # Note that the transaction_id is the id of the current instance.
      @@increment_script ||= Promiscuous::Redis::Script.new <<-SCRIPT
        local prefix = ARGV[1] .. ':'
        local operation_recovery_key = ARGV[2]
        local versions_recovery_key = operation_recovery_key .. ':versions'
        local operation_recovery_payload = ARGV[3]
        local deps = KEYS

        local versions = {}

        if redis.call('exists', versions_recovery_key) == 1 then
          for i, dep in ipairs(deps) do
            versions[i] = tonumber(redis.call('hget', versions_recovery_key, dep))
            if not versions[i] then
              return redis.error_reply('Failed to read dependency ' .. dep .. ' during recovery')
            end
          end

          return { versions }
        end

        for i, dep in ipairs(deps) do
          local key = prefix .. dep
          versions[i] = redis.call('incr', key .. ':w')
          redis.call('hset', versions_recovery_key, dep, versions[i])
        end

        if operation_recovery_payload then
          redis.call('set', operation_recovery_key, operation_recovery_payload)
        end

        return { versions }
      SCRIPT

      versions = @@increment_script.eval(node, :argv => argv, :keys => deps)

      deps.zip(versions).each  { |dep, version| dep.version = version }

      @committed_write_deps += deps
    end

    # The instance version must to be the first in the list to allow atomic
    # subscribers to do their magic.
    # TODO What happens with transactions with multiple operations?
    instance_dep_index = @committed_write_deps.index(write_dependencies.first)
    @committed_write_deps[0], @committed_write_deps[instance_dep_index] =
      @committed_write_deps[instance_dep_index], @committed_write_deps[0]
  end

  def self.lock_options
    {
      :timeout  => 10.seconds,   # after 10 seconds, we give up so we don't queue requests
      :sleep    => 0.01.seconds, # polling every 10ms.
      :expire   => 1.minute,     # after one minute, we are considered dead
      :lock_set => Promiscuous::Key.new(:pub).join('lock_set').to_s
    }
  end
  delegate :lock_options, :to => self

  def dependency_for_op_lock
    query_dependencies.first
  end

  def get_new_op_lock
    dep = dependency_for_op_lock
    Promiscuous::Redis::Mutex.new(dep.key(:pub).to_s, lock_options.merge(:node => dep.redis_node))
  end

  def self._acquire_lock(mutex)
    loop do
      case mutex.lock
      # recover_operation_from_lock implicitely unlocks the lock.
      when :recovered then recover_operation_from_lock(mutex)
      when true       then return true
      when false      then return false
      end
    end
  end

  def acquire_op_lock
    @op_lock = get_new_op_lock

    unless self.class._acquire_lock(@op_lock)
      raise Promiscuous::Error::LockUnavailable.new(@op_lock.key)
    end
  end

  def release_op_lock
    @op_lock.unlock
    @op_lock = nil
  end

  def ensure_op_still_locked
    unless @op_lock.still_locked?
      # We lost the lock, let the recovery mechanism do its thing.
      raise Promiscuous::Error::LostLock.new(@op_lock.key)
    end
  end

  def self.recover_locks
    return unless Promiscuous::Redis.master
    # This method is regularly called from a worker to recover locks by doing a
    # locking/unlocking cycle.

    Promiscuous::Redis.master.nodes.each do |node|
      loop do
        key, time = node.zrange(lock_options[:lock_set], 0, 1, :with_scores => true).flatten
        break unless key && Time.now.to_i >= time.to_i + lock_options[:expire]

        mutex = Promiscuous::Redis::Mutex.new(key, lock_options.merge(:node => node))
        mutex.unlock if _acquire_lock(mutex)
      end
    end
  end
  register_recovery_mechanism :recover_locks

  def dependencies_for(instance, options={})
    return [] if instance.nil?

    # Note that tracked_dependencies will not return the id dependency if it
    # doesn't exist which can only happen for create operations and auto
    # generated ids.
    [instance.promiscuous.get_dependency]
  end

  def write_dependencies
    @write_dependencies ||= self.query_dependencies.uniq.each { |d| d.type = :write }
  end

  def should_instrument_query?
    !Promiscuous.disabled?
  end

  def execute(&query_config)
    query = Promiscuous::Publisher::Operation::ProxyForQuery.new(self, &query_config)

    if should_instrument_query?
      execute_instrumented(query)
    else
      query.call_and_remember_result(:non_instrumented)
    end

    query.result
  end

  def query_dependencies
    # Returns the list of dependencies that are involved in the database query.
    # For an atomic write operation, the first one returned must be the one
    # corresponding to the primary key.
    raise
  end

  def execute_instrumented(db_operation)
    # Implemented by subclasses
    raise
  end

  def operation_payloads
    # subclass can use payloads_for to generate the payload
    raise
  end

  def recovery_payload
    # Overridden to be able to recover the operation
    []
  end

  def self.recover_operation(*recovery_payload)
    # Overridden to reconstruct the operation.
  end

  def recover_db_operation
    # Overridden to reexecute the db operation during recovery (or make sure that
    # it will never succeed).
  end

  def trace_operation
    if ENV['TRACE']
      msg = self.explain_operation(70)
      Promiscuous.context.trace(msg, :color => '1;31')
    end
  end

  def explain_operation(max_width)
    "Unknown database operation"
  end
end
