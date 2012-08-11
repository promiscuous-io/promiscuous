module Promiscuous
  module AMQP
    module Bunny
      mattr_accessor :connection

      def self.configure(options)
        require 'bunny'
        self.connection = ::Bunny.new(options[:server_uri])
        self.connection.start
      end

      def self.publish(msg)
        AMQP.info "[publish] #{msg[:key]} -> #{msg[:payload]}"
        exchange = connection.exchange('promiscuous', :type => :topic, :durable => true)
        exchange.publish(msg[:payload], :key => msg[:key], :persistent => true)
      end

      def self.close
        self.connection.stop
      end
    end
  end
end
