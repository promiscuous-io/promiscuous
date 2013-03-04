module Promiscuous::AMQP::Bunny
  def self.hijack_bunny
    return if @bunny_hijacked
    ::Bunny::Session.class_eval do
      alias_method :handle_network_failure_without_promiscuous, :handle_network_failure

      def handle_network_failure(e)
        Promiscuous.warn "[amqp] #{e}. Reconnecting..."
        Promiscuous::Config.error_notifier.try(:call, e)
        handle_network_failure_without_promiscuous(e)
      end
    end
    @bunny_hijacked = true
  end

  mattr_accessor :connection, :connection_lock
  # The bunnet socket doesn't like when multiple threads access to it apparently
  self.connection_lock = Mutex.new

  def self.connect
    require 'bunny'
    hijack_bunny

    return if connected?
    self.connection = ::Bunny.new(Promiscuous::Config.amqp_url,
                                  :heartbeat_interval => Promiscuous::Config.heartbeat)
    self.connection.start

    @master_channel = self.connection.create_channel
    @master_exchange = exchange(@master_channel)
  end

  def self.disconnect
    connection_lock.synchronize do
      return unless connected?
      self.connection.stop
    end
  end

  def self.connected?
    !!self.connection.try(:connected?)
  end

  def self.publish(options={})
    connection_lock.synchronize do
      @master_exchange.publish(options[:payload], :key => options[:key], :persistent => true)
    end
  end

  def self.exchange(channel)
    channel.exchange(Promiscuous::AMQP::EXCHANGE, :type => :topic, :durable => true)
  end

  module CelluloidSubscriber
    def subscribe(options={}, &block)
      queue_name    = options[:queue_name]
      bindings      = options[:bindings]
      Promiscuous::AMQP.ensure_connected

      Promiscuous::AMQP::Bunny.connection_lock.synchronize do
        @channel = Promiscuous::AMQP::Bunny.connection.create_channel
        @channel.prefetch(Promiscuous::Config.prefetch)
        exchange = Promiscuous::AMQP::Bunny.exchange(@channel)
        queue = @channel.queue(queue_name, Promiscuous::Config.queue_options)
        bindings.each do |binding|
          queue.bind(exchange, :routing_key => binding)
          Promiscuous.debug "[bind] #{queue_name} -> #{binding}"
        end
        @subscription = queue.subscribe(:ack => true) do |delivery_info, metadata, payload|
          block.call(MetaData.new(self, delivery_info), payload)
        end
      end
    end

    def ack_message(tag)
      Promiscuous::AMQP::Bunny.connection_lock.synchronize do
        @channel.ack(tag)
      end
    end

    class MetaData
      def initialize(subscriber, delivery_info)
        @subscriber = subscriber
        @delivery_info = delivery_info
      end

      def ack
        @subscriber.ack_message(@delivery_info.delivery_tag)
      end
    end

    def wait_for_subscription
      # Nothing to do, things are synchronous.
    end

    def finalize
      Promiscuous::AMQP::Bunny.connection_lock.synchronize do
        @channel.close
      end
    end

    def recover
      @channel.recover
    end
  end
end
