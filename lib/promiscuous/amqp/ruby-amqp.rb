module Promiscuous
  module AMQP
    module RubyAMQP
      mattr_accessor :channel, :queue_options

      def self.configure(options)
        require 'amqp'
        connection = ::AMQP.connect(build_connection_options(options))
        self.channel = ::AMQP::Channel.new(connection)
        self.queue_options = options[:queue_options] || {:durable => true, :arguments => {'x-ha-policy' => 'all'}}
      end

      def self.build_connection_options(options)
        if options[:server_uri]
          uri = URI.parse(options[:server_uri])
          raise "Please use amqp://user:password@host:port/vhost" if uri.scheme != 'amqp'

          {
            :host => uri.host,
            :port => uri.port,
            :scheme => uri.scheme,
            :user => uri.user,
            :pass => uri.password,
            :vhost => uri.path.empty? ? "/" : uri.path,
         }
        end
      end

      def self.subscribe(options={}, &block)
        queue_name = options[:queue_name]
        bindings   = options[:bindings]

        queue = self.channel.queue(queue_name, self.queue_options)
        exchange = channel.topic('promiscuous', :durable => true)
        bindings.each do |binding|
          queue.bind(exchange, :routing_key => binding)
          AMQP.info "[bind] #{queue_name} -> #{binding}"
        end
        queue.subscribe(:ack => true, &block)
      end

      def self.publish(msg)
        AMQP.info "[publish] #{msg[:key]} -> #{msg[:payload]}"
        exchange = channel.topic('promiscuous', :durable => true)
        exchange.publish(msg[:payload], :routing_key => msg[:key], :persistent => true)
      end

      def self.close
        channel.close
      end
    end
  end
end
