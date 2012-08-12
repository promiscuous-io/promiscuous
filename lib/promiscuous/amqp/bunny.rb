module Promiscuous
  module AMQP
    module Bunny
      mattr_accessor :connection

      def self.connect
        require 'bunny'
        self.connection = ::Bunny.new(Promiscuous::Config.server_uri)
        self.connection.start
      end

      def self.disconnect
        self.connection.stop
      end

      def self.publish(msg)
        Promiscuous.info "[publish] #{msg[:key]} -> #{msg[:payload]}"
        exchange = connection.exchange('promiscuous', :type => :topic, :durable => true)
        exchange.publish(msg[:payload], :key => msg[:key], :persistent => true)
      end

      def self.subscribe(options={}, &block)
        raise "Cannot subscribe with bunny"
      end
    end
  end
end
