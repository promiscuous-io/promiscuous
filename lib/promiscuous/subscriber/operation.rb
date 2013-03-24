class Promiscuous::Subscriber::Operation
  attr_accessor :payload

  delegate :model, :id, :operation, :message, :to => :payload

  def initialize(payload)
    self.payload = payload
  end

  # XXX TODO Code is not tolerent to losing a lock.

  def update_dependencies_single(node_with_deps)
    master_node = node_with_deps[0]
    deps = node_with_deps[1]

    @@update_script ||= Promiscuous::Redis::Script.new <<-SCRIPT
      for i, key in ipairs(KEYS) do
        local v = redis.call('incr', key .. ':rw')
        redis.call('publish', key .. ':rw', v)
      end
    SCRIPT
    keys = deps.map { |dep| dep.key(:sub).to_s }
    @@update_script.eval(master_node, :keys => keys)
  end

  def update_dependencies_multi(nodes_with_deps)
    # With multi nodes, we have to do a 2pc for the lock recovery mechanism:
    # 1) We do the secondaries first, with a recovery payload.
    # 2) Then we do the master.
    # 3) Then we cleanup the secondaries.
    # We use a recovery_key unique to the operation to avoid any trouble of
    # touching another operation.
    secondary_nodes_with_deps = nodes_with_deps[1..-1]
    recovery_key = @instance_dep.key(:sub).join(@instance_dep.version).to_s

    secondary_nodes_with_deps.each do |node, deps|
      @@update_script_secondary ||= Promiscuous::Redis::Script.new <<-SCRIPT
        local recovery_key = ARGV[1]

        if redis.call('get', recovery_key) == 'done' then
          return
        end

        for i, key in ipairs(KEYS) do
          local v = redis.call('incr', key .. ':rw')
          redis.call('publish', key .. ':rw', v)
        end

        redis.call('set', recovery_key, 'done')
      SCRIPT
      keys = deps.map { |dep| dep.key(:sub).to_s }
      @@update_script_secondary.eval(node, :keys => keys, :argv => [recovery_key])
    end

    update_dependencies_single(nodes_with_deps.first)

    secondary_nodes_with_deps.each do |node, deps|
      node.del(recovery_key)
    end
  end

  def update_dependencies
    dependencies = message.dependencies[:read] + message.dependencies[:write]
    nodes_with_deps = dependencies.group_by(&:redis_node).to_a

    nodes_with_deps.size == 1 ? update_dependencies_single(nodes_with_deps.first) :
                                update_dependencies_multi(nodes_with_deps)
  end

  def verify_dependencies
    # Backward compatibility, no dependencies.
    return unless message.dependencies[:write].present?
    key = @instance_dep.key(:sub).join('rw').to_s
    return if @instance_dep.redis_node.get(key).to_i == @instance_dep.version

    raise Promiscuous::Error::AlreadyProcessed
  end

  LOCK_OPTIONS = { :timeout => 1.5.minute, # after 1.5 minute , we give up
                   :sleep   => 0.1,       # polling every 100ms.
                   :expire  => 1.minute }  # after one minute, we are considered dead

  def with_instance_dependencies
    return yield unless message && message.has_dependencies?

    @instance_dep = message.happens_before_dependencies.first
    lock_options = LOCK_OPTIONS.merge(:node => @instance_dep.redis_node)
    mutex = Promiscuous::Redis::Mutex.new(@instance_dep.key(:sub).to_s, lock_options)

    # XXX TODO recovery
    unless mutex.lock
      raise Promiscuous::Error::LockUnavailable.new(mutex.key)
    end

    begin
      verify_dependencies
      result = yield
      update_dependencies
      result
    ensure
      unless mutex.unlock
        # TODO Be safe in case we have a duplicate message and lost the lock on it
        raise "The subscriber lost the lock during its operation. It means that someone else\n"+
              "received a duplicate message, and we got screwed.\n"
      end
    end
  end

  def create
    model.__promiscuous_fetch_new(id).tap do |instance|
      instance.__promiscuous_update(payload)
      instance.save!
    end
  rescue Exception => e
    # TODO Abstract the duplicated index error message
    if e.message =~ /E11000 duplicate key error index: .*\.\$_id_ +dup key/
      Promiscuous.warn "[receive] ignoring already created record #{message.payload}"
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

  def operation
    # We must process messages with versions to stay in sync even if we
    # don't have a subscriber.
    payload.model.nil? ? :dummy : payload.operation
  end

  def commit
    with_instance_dependencies do
      case operation
      when :create  then create
      when :update  then update
      when :destroy then destroy
      when :dummy   then nil
      end
    end
  end
end
