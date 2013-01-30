require 'redis'

module Promiscuous::Redis
  mattr_accessor :connection

  def self.connect
    self.connection = ::Redis.new(:url => Promiscuous::Config.redis_uri)
  end

  def self.method_missing(name, *args, &block)
    self.connection.__send__(name, *args, &block)
  end
end
