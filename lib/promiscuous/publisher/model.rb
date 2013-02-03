require 'crowdtap_redis_lock'

module Promiscuous::Publisher::Model
  extend Promiscuous::Autoload
  autoload :ActiveRecord, :Mongoid

  extend ActiveSupport::Concern
  include Promiscuous::Publisher::Envelope

  mattr_accessor :klasses
  self.klasses = []

  def operation
    options[:operation]
  end

  def fetch
    case operation
    when :create  then instance
    when :update  then options[:fetch_proc].call
    when :destroy then nil
    end
  end

  def payload
    super.merge(:id => instance.id, :operation => operation, :version => version)
  end

  def include_attributes?
    !operation.in? [:destroy, :dummy]
  end

  def instance
    @new_instance || super
  end

  def with_lock(&block)
    return yield if Promiscuous::Config.backend == :null
    return yield if operation == :create

    key = Promiscuous::Redis.pub_key(instance.id)
    # We'll block for 60 seconds before raising an exception
    ::RedisLock.new(Promiscuous::Redis, key).retry(300).every(0.2).lock_for_update(&block)
  end

  def version
    {:global => @global_version}
  end

  def update_dependencies
    @global_version = Promiscuous::Redis.incr(Promiscuous::Redis.pub_key('global'))
  end

  def commit
    ret = nil
    exception = nil

    Promiscuous::AMQP.ensure_connected

    with_lock do
      update_dependencies
      begin
        ret = yield
      rescue Exception => e
        # we must publish something so the subscriber can sync
        # with the updated dependencies
        options[:operation] = :dummy
        exception = e
      end

      begin
        @new_instance = fetch
      rescue Exception => e
        raise_out_of_sync(e, payload.to_json)
      end
    end

    publish

    raise exception if exception
    ret
  end


  module ClassMethods
    def setup_class_binding
      super
      Promiscuous::Publisher::Model.klasses << klass
    end
  end
end
