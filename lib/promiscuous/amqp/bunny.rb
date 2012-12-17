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

      def self.publish(options={})
        Promiscuous.info "[publish] (#{options[:exchange_name]}) #{options[:key]} -> #{options[:payload]}"
        exchange(options[:exchange_name]).
          publish(options[:payload], :key => options[:key], :persistent => true)
      end

      def self.open_queue(options={}, &block)
        raise "Cannot open queue with bunny"
      end

      def self.exchange(name)
        connection.exchange(name, :type => :topic, :durable => true)
      end
    end
  end
end
