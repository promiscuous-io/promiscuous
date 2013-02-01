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

  def version
    {:global => @global_version}
  end

  def payload
    if @dummy_commit
      {:version => version, :operation => :dummy}
    else
      super.merge(:id => instance.id, :operation => operation, :version => version)
    end
  end

  def include_attributes?
    operation != :destroy
  end

  def with_lock(&block)
    return yield if operation == :create

    key = Promiscuous::Redis.pub_key(instance.id)
    ::RedisLock.new(Promiscuous::Redis, key).retry(50.times).every(0.2).lock_for_update(&block)
  end

  def instance
    @new_instance || super
  end

  def commit
    ret = nil
    exception = nil

    with_lock do
      @global_version = Promiscuous::Redis.incr(Promiscuous::Redis.pub_key('global'))
      begin
        ret = yield
      rescue Exception => e
        # save it for later
        @dummy_commit = true
        exception = e
      end


      begin
        @new_instance = fetch
      rescue Exception => e
        raise_out_of_sync(e)
      end
    end

    # We always need to publish so that the subscriber can keep up
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
