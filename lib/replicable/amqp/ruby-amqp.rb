module Replicable
  module AMQP
    module RubyAMQP
      mattr_accessor :channel, :queue_options

      def self.configure(options = {})
        require 'amqp'
        connection = ::AMQP.connect
        self.channel = ::AMQP::Channel.new(connection)
        self.queue_options = options[:queue_options] || {}
      end

      def self.subscribe(queue_name, bindings, &block)
        queue = self.channel.queue(queue_name, self.queue_options)
        exchange = channel.topic('main')
        bindings.each { |binding| queue.bind(exchange, :routing_key => binding) }
        queue.subscribe(&block)
      end

    end
  end
end
