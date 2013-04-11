class Promiscuous::Subscriber::Operation
  attr_accessor :payload

  delegate :model, :id, :operation, :message, :to => :payload
  delegate :write_dependencies, :read_dependencies, :dependencies, :to => :message

  def initialize(payload)
    @payload = payload
  end

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
    unless message.try(:has_dependencies?)
      # TODO Is this block relevant? Remove if not.
      yield
      message.ack
      return
    end

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

  def create(options={})
    model.__promiscuous_fetch_new(id).tap do |instance|
      instance.__promiscuous_update(payload)
      instance.save!
    end
  rescue Exception => e
    # TODO Abstract the duplicated index error message
    if e.message =~ /E11000 duplicate key error index: .*\.\$_id_ +dup key/
      if options[:upsert]
        update
      else
        Promiscuous.warn "[receive] ignoring already created record #{message.payload}"
      end
    else
      raise e
    end
  end

  def update
    model.__promiscuous_fetch_existing(id).tap do |instance|
      instance.__promiscuous_update(payload)
      instance.save!
    end
  rescue model.__promiscuous_missing_record_exception
    Promiscuous.warn "[receive] upserting #{message.payload}"
    create
  end

  def destroy
    model.__promiscuous_fetch_existing(id).tap do |instance|
      instance.destroy
    end
  rescue model.__promiscuous_missing_record_exception
    Promiscuous.warn "[receive] ignoring missing record #{message.payload}"
  end

  # XXX Bootstrapping is a WIP. Here's what's left to do:
  # - Promiscuous::Subscriber::Operation#bootstrap_missing_data is not implemented
  #   properly (see comment in code)
  # - Automatic switching from pass1, pass2, pass3, live
  # - Unbinding the bootstrap exchange when going live, and reset prefetch
  # - The publisher should upgrade its read dependencies into write dependencies
  #   during the version bootstrap phase.
  # - CLI interface and progress bars

  def bootstrap_versions
    keys = message.parsed_payload['keys']
    keys.map { |k| Promiscuous::Dependency.parse(k, :owner => message.parsed_payload['__amqp__']) }.group_by(&:redis_node).each do |node, deps|
      node.pipelined do
        deps.each do |dep|
          node.set(dep.key(:sub).join('rw').to_s, dep.version)
        end
      end
    end
  end

  def bootstrap_data
    if instance_dep.version <= get_current_instance_version
      create(:upsert => true)
    else
      # We don't save the instance if we don't have a matching version in redis.
      # It would mean that the document got update since the bootstrap_versions.
      # We'll get it on the next pass. But we should remember what we've dropped
      # to be able to know when we can go live
    end
  end

  def bootstrap_missing_data
    # TODO XXX How do we know what is the earliest instance?
    # TODO Remember what instances we've dropped (the else block in the
    # bootstrap_data method)
    create(:upsert => true)
  end

  def on_bootstrap_operation(wanted_operation, options={})
    if operation == wanted_operation
      yield
      options[:always_postpone] ? message.postpone : message.ack
    else
      message.postpone
    end
  end

  def commit
    case Promiscuous::Config.bootstrap
    when :pass1
      # The first thing to do is to receive and save an non atomic snapshot of
      # the publisher's versions.
      on_bootstrap_operation(:bootstrap_versions) { bootstrap_versions }

    when :pass2
      # Then we move on to save the raw data, but skipping the message if we get
      # a mismatch on the version.
      on_bootstrap_operation(:bootstrap_data) { bootstrap_data }

    when :pass3
      # Finally, we create the rows that we've skipped, we postpone them to make
      # our lives easier. We'll detect the message as duplicates when re-processed.
      on_bootstrap_operation(:update, :always_postpone => true) { bootstrap_missing_data if model }

      # TODO unbind the bootstrap exchange
    else
      synchronize_and_update_dependencies do
        case operation
        when :create  then create  if model
        when :update  then update  if model
        when :destroy then destroy if model
        when :dummy   then ;
        else raise "Invalid operation received: #{operation}"
        end
      end
    end
  end
end
