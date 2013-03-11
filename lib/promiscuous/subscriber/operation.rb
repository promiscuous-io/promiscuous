class Promiscuous::Subscriber::Operation
  attr_accessor :payload

  delegate :model, :id, :operation, :message, :to => :payload

  def initialize(payload)
    self.payload = payload
  end

  def update_dependencies
    dependencies = message.dependencies[:read] + message.dependencies[:write]

    @@update_script_sha ||= Promiscuous::Redis.script(:load, <<-SCRIPT)
      local versions = {}
      for i, key in ipairs(KEYS) do
        versions[i] = redis.call('incr', key .. ':rw')
        redis.call('publish', key .. ':rw', versions[i])
      end

      return versions
    SCRIPT
    versions = Promiscuous::Redis.evalsha(@@update_script_sha,
               :keys => dependencies.map { |dep| dep.key(:sub).to_s })

    # This caches the current version, in case we need it again.
    # TODO Evaluate if it's better with or without.
    if synchronizer = Celluloid::Actor[:message_synchronizer]
      dependencies.zip(versions).each do |dep, version|
        synchronizer.async.try_notify_key_change(dep.key(:sub).join('rw').to_s, version)
      end
    end
  end

  def verify_dependencies
    if message.dependencies[:write].present?
      # We take the first write depedency (adjusted with the read increments)
      key = @instance_dep.key(:sub).join('rw').to_s
      if Promiscuous::Redis.get(key).to_i != @instance_dep.version
        raise Promiscuous::Error::AlreadyProcessed
      end
    end
  end

  LOCK_OPTIONS = { :timeout => 1.5.minute, # after 1.5 minute , we give up
                   :sleep   => 0.1,       # polling every 100ms.
                   :expire  => 1.minute }  # after one minute, we are considered dead

  def with_instance_dependencies
    return yield unless message && message.has_dependencies?

    @instance_dep = message.happens_before_dependencies.first
    mutex = Promiscuous::Redis::Mutex.new(@instance_dep.key(:sub).to_s, LOCK_OPTIONS)

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
