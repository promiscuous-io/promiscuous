require 'crowdtap_redis_lock'

module Promiscuous::Publisher::Model
  extend Promiscuous::Autoload
  autoload :Generic

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
end
