class Promiscuous::Subscriber::MessageProcessor::Regular < Promiscuous::Subscriber::MessageProcessor::Base
  delegate :write_dependencies, :read_dependencies, :dependencies, :to => :message

  def nodes_with_deps
    @nodes_with_deps ||= dependencies.group_by(&:redis_node)
  end

  def instance_dep
    @instance_dep ||= write_dependencies.first
  end

  def master_node
    @master_node ||= instance_dep.redis_node
  end

  def master_node_with_deps
    @master_node_with_deps ||= nodes_with_deps.select { |node| node == master_node }.first
  end

  def secondary_nodes_with_deps
    @secondary_nodes_with_deps ||= nodes_with_deps.reject { |node| node == master_node }.to_a
  end

  def recovery_key
    # We use a recovery_key unique to the operation to avoid any trouble of
    # touching another operation.
    @recovery_key ||= instance_dep.key(:sub).join(instance_dep.version).to_s
  end

  def get_current_instance_version
    master_node.get(instance_dep.key(:sub).join('rw').to_s).to_i
  end

  # XXX TODO Code is not tolerant to losing a lock.

  def update_dependencies_on_node(node_with_deps, options={})
    # Read and write dependencies are not handled the same way:
    # * Read dependencies are just incremented (which allow parallelization).
    # * Write dependencies are set to be max(current_version, received_version).
    #   This allow the version bootstrapping process to be non-atomic.
    #   Publishers upgrade their reads dependencies to write dependencies
    #   during bootstrapping to permit the mechanism to function properly.

    # TODO Evaluate the performance hit of this heavy mechanism, and see if it's
    # worth optimizing it for the non-bootstrap case.

    node = node_with_deps[0]
    r_deps = node_with_deps[1].select(&:read?)
    w_deps = node_with_deps[1].select(&:write?)

    if options[:only_write_dependencies]
      r_deps = []
    end

    argv = []
    argv << MultiJson.dump([r_deps.map { |dep| dep.key(:sub) },
                            w_deps.map { |dep| dep.key(:sub) },
                            w_deps.map { |dep| dep.version }])
    argv << recovery_key if options[:with_recovery]

    @@update_script_secondary ||= Promiscuous::Redis::Script.new <<-SCRIPT
      local _args = cjson.decode(ARGV[1])
      local read_deps = _args[1]
      local write_deps = _args[2]
      local write_versions = _args[3]
      local recovery_key = ARGV[2]

      if recovery_key and redis.call('exists', recovery_key) == 1 then
        return
      end

      for i, _key in ipairs(read_deps) do
        local key = _key .. ':rw'
        local v = redis.call('incr', key)
        redis.call('publish', key, v)
      end

      for i, _key in ipairs(write_deps) do
        local key = _key .. ':rw'
        local v = write_versions[i]
        local current_version = tonumber(redis.call('get', key)) or 0
        if current_version < v then
          redis.call('set', key, v)
          redis.call('publish', key, v)
        end
      end

      if recovery_key then
        redis.call('set', recovery_key, 'done')
      end
    SCRIPT

    @@update_script_secondary.eval(node, :argv => argv)
  end

  def update_dependencies_master(options={})
    update_dependencies_on_node(master_node_with_deps, options)
  end

  def update_dependencies_secondaries(options={})
    secondary_nodes_with_deps.each do |node_with_deps|
      update_dependencies_on_node(node_with_deps, options.merge(:with_recovery => true))
      after_secondary_update_hook
    end
  end

  def after_secondary_update_hook
    # Hook only used for testing
  end

  def cleanup_dependency_secondaries
    secondary_nodes_with_deps.each do |node, deps|
      node.del(recovery_key)
    end
  end

  def update_dependencies(options={})
    # With multi nodes, we have to do a 2pc for the lock recovery mechanism:
    # 1) We do the secondaries first, with a recovery token.
    # 2) Then we do the master.
    # 3) Then we cleanup the recovery token on secondaries.
    update_dependencies_secondaries(options)
    update_dependencies_master(options)
    cleanup_dependency_secondaries
  end

  def check_for_duplicated_message
    unless instance_dep.version >= get_current_instance_version + 1
      # We happen to get a duplicate message, or we are recovering a dead
      # worker. During regular operations, we just need to cleanup the 2pc (from
      # the dead worker), and ack the message to rabbit.
      # TODO Test cleanup
      cleanup_dependency_secondaries

      # But, if the message was generated during bootstrap, we don't really know
      # if the other dependencies are up to date (because of the non-atomic
      # bootstrapping process), so we do the max() trick (see in update_dependencies_on_node).
      # Since such messages can come arbitrary late, we never really know if we
      # can assume regular operations, thus we always assume that such message
      # can originate from the bootstrapping period.
      # Note that we are not in the happy path. Such duplicates messages are
      # seldom: either (1) the publisher recovered a payload that didn't need
      # recovery, or (2) a subscriber worker died after # update_dependencies_master,
      # but before the message acking).
      # It is thus okay to assume the worse and be inefficient.
      update_dependencies(:only_write_dependencies => true)

      message.ack

      raise Promiscuous::Error::AlreadyProcessed
    end
  end

  LOCK_OPTIONS = { :timeout => 1.5.minute, # after 1.5 minute, we give up
                   :sleep   => 0.1,        # polling every 100ms.
                   :expire  => 1.minute }  # after one minute, we are considered dead

  def synchronize_and_update_dependencies
    if Promiscuous::Config.bootstrap
    else
      lock_options = LOCK_OPTIONS.merge(:node => master_node)
      mutex = Promiscuous::Redis::Mutex.new(instance_dep.key(:sub).to_s, lock_options)

      unless mutex.lock
        raise Promiscuous::Error::LockUnavailable.new(mutex.key)
      end

      begin
        check_for_duplicated_message
        yield
        update_dependencies
        message.ack
      ensure
        unless mutex.unlock
          # TODO Be safe in case we have a duplicate message and lost the lock on it
          raise "The subscriber lost the lock during its operation. It means that someone else\n"+
            "received a duplicate message, and we got screwed.\n"
        end
      end
    end
  end

  def on_message
    self.synchronize_and_update_dependencies do
      self.operations.each(&:execute)
    end
  end

  def operation_class
    Promiscuous::Subscriber::Operation::Regular
  end
end
