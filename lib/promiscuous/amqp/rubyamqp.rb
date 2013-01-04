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
        self.channel = ::AMQP::Channel.new(connection, :auto_recovery => true)

        connection.on_tcp_connection_loss do |conn|
          unless conn.reconnecting?
            Promiscuous.warn "[connection] Lost connection. Reconnecting..."
            conn.periodically_reconnect(2)

            exception = StandardError.new 'Lost connection'
            Promiscuous::Config.error_handler.try(:call, exception)

            Promiscuous::Worker.pause # TODO XXX This doesn't belong here
          end
        end

        connection.on_recovery do |conn|
          Promiscuous.warn "[connection] Reconnected"
          Promiscuous::Worker.resume # TODO XXX This doesn't belong here
        end

        connection.on_error do |conn, conn_close|
          # No need to handle CONNECTION_FORCED since on_tcp_connection_loss takes
          # care of it.
          Promiscuous.warn "[connection] #{conn_close.reply_text}"
        end
      end

      def self.disconnect
        if self.channel && self.channel.connection.connected?
          self.channel.connection.close
          self.channel.close
        end
        self.channel = nil
      end

      def self.connected?
        !!self.channel.try(:connection).try(:connected?)
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
        info_msg = "(#{options[:exchange_name]}) #{options[:key]} -> #{options[:payload]}"

        unless channel.connection.connected?
          exception = StandardError.new 'Lost connection'
          raise Promiscuous::Publisher::Error.new(exception, info_msg)
        end

        Promiscuous.info "[publish] #{info_msg}"
        exchange(options[:exchange_name]).
          publish(options[:payload], :routing_key => options[:key], :persistent => true)
      end

      def self.exchange(name)
        channel.topic(name, :durable => true)
      end
    end
  end
end
