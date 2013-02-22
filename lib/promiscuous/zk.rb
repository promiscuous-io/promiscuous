# zk depends on Logging, but libv8 requires mkmf which set its own ::Logging
if defined?(::Logging) && ::Logging.respond_to?(:postpone)
  Object.__send__(:remove_const, :Logging)
end

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
    if Promiscuous::Config.backend == :null
      return Null.new
    end

    unless Promiscuous::Config.zookeeper_hosts
      Promiscuous.warn "[zookeeper] Running without zookeeper"
      return Null.new
    end

    zk = ::ZK.new(Promiscuous::Config.zookeeper_hosts)
    zk.wait_until_connected
    zk
  end

  def self.lost_connection_exception
    Promiscuous::Error::Connection.new(:service => :zookeeper)
  end

  def self.ensure_connected
    raise lost_connection_exception unless master.ping?
  end

  def self.ensure_connected
    Promiscuous::ZK.master.ping
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

    def with_lock(*args, &block)
      block.call
    end
  end

  class MultiLock
    def initialize(zk=nil)
      @zk = zk || Promiscuous::ZK
      @locks = []
    end

    def add(path, options={})
      @locks << {:path => path, :options => options}
    end
    alias :<< :add

    def acquire(&block)
      # Sorting avoids deadlocks
      @locks.sort! { |a,b| a[:path] <=> b[:path] }
      @locks.uniq!

      # It would be nice to have a fast multi lock
      @locks.reduce(block) do |chain, lock|
        proc { @zk.with_lock(lock[:path], lock[:options], &chain) }
      end.call
    end
  end
end
