module Replicable
  module AMQP
    module RubyAMQP
      mattr_accessor :channel, :queue_options

      def self.configure(options)
        require 'amqp'
        connection = ::AMQP.connect
        self.channel = ::AMQP::Channel.new(connection)
        self.queue_options = options[:queue_options] || {}
      end

      def self.subscribe(options={}, &block)
        queue_name = options[:queue_name]
        bindings   = options[:bindings]

        queue = self.channel.queue(queue_name, self.queue_options)
        exchange = channel.topic('replicable')
        bindings.each do |binding|
          queue.bind(exchange, :routing_key => binding)
          AMQP.logger.info "[bind] #{queue_name} -> #{binding}"
        end
        queue.subscribe(:ack => true, &block)
      end

      def self.publish(msg)
        exchange = channel.topic('replicable')
        exchange.publish(msg[:payload], :routing_key => msg[:key])
        AMQP.logger.info "[publish] #{msg[:key]} -> #{msg[:payload]}"
      end

      def self.close
        channel.close
      end
    end
  end
end
