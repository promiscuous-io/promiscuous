require 'crowdtap_redis_lock'

module Promiscuous::Subscriber::Model
  extend ActiveSupport::Concern
  include Promiscuous::Subscriber::Envelope

  def fetch_new
    if foreign_key
      klass.new(foreign_key => id)
    else
      klass.new.tap { |o| o.id = id }
    end
  end

  def fetch_existing
    if foreign_key
      if klass.respond_to?("find_by_#{foreign_key}!")
        klass.__send__("find_by_#{foreign_key}!", id)
      elsif klass.respond_to?("find_by")
        klass.find_by(foreign_key => id)
      else
        record = klass.where(foreign_key => id).first
        raise self.class.missing_record_exception.new(klass, id) if record.nil?
        record
      end
    else
      klass.find(id)
    end
  end

  def fetch
    case operation
    when :create  then fetch_new
    when :update  then fetch_existing
    when :destroy then fetch_existing
    when :dummy   then fetch_new
    end
  end

  def process_attributes?
    !operation.in? [:destroy, :dummy]
  end

  def message
    options[:message]
  end

  def with_lock(&block)
    return yield if Promiscuous::Config.backend == :null

    key = Promiscuous::Redis.sub_key(instance.id)
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

  def with_dependencies
    return yield unless message && message.has_dependencies?

    with_lock do
      if verify_dependencies
        yield
        update_dependencies
      else
        Promiscuous.info "[receive] (skipped, already processed) #{message.payload}"
      end
    end

    publish_dependencies
  end

  def process
    super
    commit
  end

  def commit
    with_dependencies do
      case operation
      when :create  then instance.save!
      when :update  then instance.save!
      when :destroy then instance.destroy
      when :dummy   then nil
      end
    end
  end

  included do
    use_option :foreign_key

    use_payload_attribute :id
    use_payload_attribute :operation, :symbolize => true
  end
end
