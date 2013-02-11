require 'crowdtap_redis_lock'

class Promiscuous::Subscriber::Operation
  attr_accessor :payload

  delegate :model, :id, :operation, :message, :to => :payload

  def initialize(payload)
    self.payload = payload
  end

  def with_instance_lock(&block)
    return yield if Promiscuous::Config.backend == :null

    key = Promiscuous::Redis.sub_key(id)
    # We'll block for 60 seconds before raising an exception
    ::RedisLock.new(Promiscuous::Redis, key).retry(300).every(0.2).lock_for_update(&block)
  end

  def verify_dependencies
    @global_key = Promiscuous::Redis.sub_key('global')
    Promiscuous::Redis.get(@global_key).to_i + 1 == message.global_version
  end

  def update_dependencies
    Promiscuous::Redis.set(@global_key, message.global_version)
    @changed_global_key = true
  end

  def publish_dependencies
    Promiscuous::Redis.publish(@global_key, message.global_version) if @changed_global_key
  end

  def with_instance_dependencies
    return yield unless message && message.has_dependencies?

    with_instance_lock do
      if verify_dependencies
        yield
        update_dependencies
      else
        Promiscuous.info "[receive] (skipped, already processed) #{message.payload}"
      end
    end

    publish_dependencies
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
