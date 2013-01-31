require 'redis'

module Promiscuous::Redis
  mattr_accessor :master

  def self.connect
    self.master = new_connection
  end

  def self.new_connection
    ::Redis.new(:url => Promiscuous::Config.redis_uri).tap { |r| r.client.connect }
  end

  def self.method_missing(name, *args, &block)
    self.master.__send__(name, *args, &block)
  end

  def self.pub_key(str)
    "publishers:#{Promiscuous::Config.app}:#{str}"
  end

  def self.sub_key(str)
    "subscribers:#{Promiscuous::Config.app}:#{str}"
  end
end
