module Promiscuous
  module AMQP
    module RubyAMQP
      mattr_accessor :channel

      def self.connect
        require 'amqp'

        amqp_options = if Promiscuous::Config.server_uri
          uri = URI.parse(Promiscuous::Config.server_uri)
          raise "Please use amqp://user:password@host:port/vhost" if uri.scheme != 'amqp'

          {
            :host   => uri.host,
            :port   => uri.port,
            :scheme => uri.scheme,
            :user   => uri.user,
            :pass   => uri.password,
            :vhost  => uri.path.empty? ? "/" : uri.path,
          }
        end

        connection = ::AMQP.connect(amqp_options)
        self.channel = ::AMQP::Channel.new(connection)
      end

      def self.disconnect
        self.channel.close if self.channel
        self.channel = nil
      end

      def self.open_queue(options={}, &block)
        queue_name = options[:queue_name]
        bindings   = options[:bindings]

        queue = self.channel.queue(queue_name, Promiscuous::Config.queue_options)
        bindings.each do |binding|
          queue.bind(exchange(options[:exchange_name]), :routing_key => binding)
          Promiscuous.info "[bind] #{queue_name} -> #{binding}"
        end
        block.call(queue) if block
      end

      def self.publish(options={})
        Promiscuous.info "[publish] (#{options[:exchange_name]}) #{options[:key]} -> #{options[:payload]}"
        exchange(options[:exchange_name]).
          publish(options[:payload], :routing_key => options[:key], :persistent => true)
      end

      def self.exchange(name)
        channel.topic(name, :durable => true)
      end
    end
  end
end
