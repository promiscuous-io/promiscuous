class Promiscuous::Subscriber::Operation
  attr_accessor :payload

  delegate :model, :id, :operation, :message, :to => :payload

  def initialize(payload)
    self.payload = payload
  end

  def update_dependencies
    futures = nil
    # link is not incremented
    dependencies = message.dependencies[:read] + message.dependencies[:write]
    Promiscuous::Redis.multi do
      futures = dependencies.map do |dep|
        key = dep.key(:sub).for(:redis)
        [key, Promiscuous::Redis.incr(key)]
      end
    end

    synchronizer = Celluloid::Actor[:message_synchronizer]
    futures.each do |key, future|
      synchronizer.async.try_notify_key_change(key, future.value)
    end

    Promiscuous::Redis.pipelined do
      futures.each do |key, future|
        Promiscuous::Redis.publish(key, future.value)
      end
    end
  end

  def with_instance_dependencies
    result = yield
    update_dependencies if message && message.has_dependencies?
    result
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
