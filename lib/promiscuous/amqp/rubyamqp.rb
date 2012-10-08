module Promiscuous
  module AMQP
    module RubyAMQP
      mattr_accessor :channel, :queue_options

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
        self.queue_options = Promiscuous::Config.queue_options
      end

      def self.disconnect
        self.channel.close if self.channel
        self.channel = nil
      end

      def self.subscribe(options={}, &block)
        queue_name = options[:queue_name]
        bindings   = options[:bindings]

        queue = self.channel.queue(queue_name, self.queue_options)
        exchange = channel.topic('promiscuous', :durable => true)
        bindings.each do |binding|
          queue.bind(exchange, :routing_key => binding)
          Promiscuous.info "[bind] #{queue_name} -> #{binding}"
        end
        queue.subscribe(:ack => true, &block)
      end

      def self.publish(msg)
        Promiscuous.info "[publish] #{msg[:key]} -> #{msg[:payload]}"
        exchange = channel.topic('promiscuous', :durable => true)
        exchange.publish(msg[:payload], :routing_key => msg[:key], :persistent => true)
      end
    end
  end
end
