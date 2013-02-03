require 'redis'

module Promiscuous::Redis
  mattr_accessor :master

  def self.connect
    disconnect
    self.master = new_connection
  end

  def self.disconnect
    self.master.client.disconnect if self.master
    self.master = nil
  end

  def self.new_connection
    return Null.new if Promiscuous::Config.backend == :null

    redis = ::Redis.new(:url => Promiscuous::Config.redis_url,
                        :tcp_keepalive => 60)
    redis.client.connect
    redis
  end

  def self.new_celluloid_connection
    return Null.new if Promiscuous::Config.backend == :null

    new_connection.tap do |redis|
      redis.client.connection.instance_eval do
        @sock = Celluloid::IO::TCPSocket.from_ruby_socket(@sock)
        @sock.instance_eval do
          extend ::Redis::Connection::SocketMixin
          @timeout = nil
          @buffer = ""

          def _read_from_socket(nbytes)
            readpartial(nbytes)
          end
        end
      end
    end
  end

  def self.lost_connection_exception
    Promiscuous::Error::Connection.new(:service => :redis)
  end

  def self.ensure_connected
    Promiscuous::Redis.master.ping
  rescue
    raise lost_connection_exception
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

  class Null
    def client
      return self.class.new
    end

    def method_missing(name, *args, &block)
      0
    end
  end
end
