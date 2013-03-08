class Promiscuous::AMQP::Bunny
  include Celluloid

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

  attr_accessor :connection, :connection_lock, :callback_mapping

  def initialize
    require 'bunny'
    self.class.hijack_bunny

    # The bunnet socket doesn't like when multiple threads access to it apparently
    @connection_lock = Mutex.new
    @callback_mapping = {}
  end

  def connect
    @connection = ::Bunny.new(Promiscuous::Config.amqp_url,
                              :heartbeat_interval => Promiscuous::Config.heartbeat)
    @connection.start

    @master_channel = @connection.create_channel
    @master_exchange = exchange(@master_channel)
    # Making sure that the actor gets it
    @master_channel.confirm_select(Promiscuous::AMQP.backend.method(:on_confirm))
  end

  def disconnect
    return unless connected?
    @connection_lock.synchronize do
      @master_channel.close
      @connection.stop
    end
  end

  def connected?
    @connection.connected?
  end

  def publish(options={})
    @connection_lock.synchronize do
      tag = @master_channel.next_publish_seq_no
      @master_exchange.publish(options[:payload], :key => options[:key], :persistent => true)
      @callback_mapping[tag] = options[:on_confirm] if options[:on_confirm]
    end
  rescue Exception => e
    e = Promiscuous::Error::Publisher.new(e, :payload => options[:payload])
    Promiscuous.warn "[publish] #{e} #{e.backtrace.join("\n")}"
    Promiscuous::Config.error_notifier.try(:call, e)
  end

  def on_confirm(tag, multiple, nack)
    if multiple
      cbs = @callback_mapping.keys.select { |k| k <= tag }
      .map { |k| @callback_mapping.delete(k) }
      cbs.each(&:call) if !nack
    else
      cb = @callback_mapping.delete(tag)
      cb.try(:call) if !nack
    end
  end

  def exchange(channel)
    channel.exchange(Promiscuous::AMQP::EXCHANGE, :type => :topic, :durable => true)
  end

  module CelluloidSubscriber
    def subscribe(options={}, &block)
      queue_name    = options[:queue_name]
      bindings      = options[:bindings]
      Promiscuous::AMQP.ensure_connected

      Promiscuous::AMQP.backend.connection_lock.synchronize do
        @channel = Promiscuous::AMQP.backend.connection.create_channel
        @channel.prefetch(Promiscuous::Config.prefetch)
        exchange = Promiscuous::AMQP.backend.exchange(@channel)
        @queue = @channel.queue(queue_name, Promiscuous::Config.queue_options)
        bindings.each do |binding|
          @queue.bind(exchange, :routing_key => binding)
          Promiscuous.debug "[bind] #{queue_name} -> #{binding}"
        end
        @subscription = @queue.subscribe(:ack => true) do |delivery_info, metadata, payload|
          block.call(MetaData.new(self, delivery_info), payload)
        end
      end
    end

    def ack_message(tag)
      Promiscuous::AMQP.backend.connection_lock.synchronize do
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
      Promiscuous::AMQP.backend.connection_lock.synchronize do
        @channel.close
      end
    end

    def recover
      @channel.recover
    end
  end
end
