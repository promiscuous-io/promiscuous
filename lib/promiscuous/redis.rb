require 'redis'

module Promiscuous::Redis
  mattr_accessor :master

  def self.connect
    self.master = new_connection
  end

  def self.new_connection
    return Null.new if Promiscuous::Config.backend == :null

    ::Redis.new(:url => Promiscuous::Config.redis_url).tap { |r| r.client.connect }
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
    def method_missing(name, *args, &block)
      0
    end
  end
end
