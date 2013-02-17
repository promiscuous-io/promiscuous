require 'zk'

module Promiscuous::ZK
  mattr_accessor :master

  def self.connect
    disconnect
    self.master = new_connection
  end

  def self.disconnect
    self.master.close! if self.master
    self.master = nil
  end

  def self.new_connection
    return Null.new if Promiscuous::Config.backend == :null
    ::ZK.new(Promiscuous::Config.zookeeper_hosts,
             :chroot => "/promiscuous/#{Promiscuous::Config.app}")
  end

  def self.lost_connection_exception
    Promiscuous::Error::Connection.new(:service => :zookeeper)
  end

  def self.ensure_connected
    raise lost_connection_exception unless master.ping?
  end

  def self.ensure_connected
    Promiscuous::Redis.master.ping
  rescue
    raise lost_connection_exception
  end

  def self.method_missing(name, *args, &block)
    self.master.__send__(name, *args, &block)
  end

  class Null
    def method_missing(name, *args, &block)
      0
    end
  end
end
