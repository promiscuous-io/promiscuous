require 'crowdtap_redis_lock'

module Promiscuous::Publisher::Model
  extend ActiveSupport::Concern
  include Promiscuous::Publisher::Envelope

  mattr_accessor :klasses
  self.klasses = []

  def operation
    options[:operation]
  end

  def version
    {:global => @global_version}
  end

  def payload
    super.merge(:id => instance.id, :operation => operation, :version => version)
  end

  def include_attributes?
    operation != :destroy
  end

  def with_lock(&block)
    return yield if operation == :create

    key = Promiscuous::Redis.pub_key(instance.id)
    ::RedisLock.new(Promiscuous::Redis, key).retry(50.times).every(0.2).lock_for_update(&block)
  end

  def commit_db(&block)
    with_lock do
      @global_version = Promiscuous::Redis.incr(Promiscuous::Redis.pub_key('global'))
      yield
    end
  end

  module ModelInstanceMethods
    extend ActiveSupport::Concern

    def with_promiscuous(options={}, &block)
      publisher = self.class.promiscuous_publisher.new(options.merge(:instance => self))
      ret = publisher.commit_db(&block)
      # FIXME if we die here, we are out of sync
      publisher.publish
      ret
    end

    included do
      around_create  { |&block| with_promiscuous(:operation => :create,  &block) }
      around_update  { |&block| with_promiscuous(:operation => :update,  &block) }
      around_destroy { |&block| with_promiscuous(:operation => :destroy, &block) }
    end
  end

  module ClassMethods
    def setup_class_binding
      super

      if klass && !klass.include?(ModelInstanceMethods)
        klass.__send__(:include, ModelInstanceMethods)
        Promiscuous::Publisher::Model.klasses << klass
      end
    end
  end
end
