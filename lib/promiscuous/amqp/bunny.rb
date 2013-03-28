class Promiscuous::AMQP::Bunny
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

  def initialize_driver
    require 'bunny'
    self.class.hijack_bunny
  end

  def initialize
    initialize_driver
    # The bunny socket doesn't like when multiple threads access to it apparently
    @connection_lock = Mutex.new
    @callback_mapping = {}
  end

  def connect
    @connection, @channel = new_connection
    @exchange = exchange(@channel, :pub)
    confirm_select(@channel, &method(:on_confirm))
  end

  def new_connection
    connection = ::Bunny.new(Promiscuous::Config.amqp_url,
                             :heartbeat_interval => Promiscuous::Config.heartbeat,
                             :socket_timeout     => Promiscuous::Config.socket_timeout,
                             :connect_timeout    => Promiscuous::Config.socket_timeout)
    connection.start

    channel = connection.create_channel
    [connection, channel]
  end

  def disconnect
    @connection_lock.synchronize do
      return unless connected?
      @connection.stop
      @connection = @channel = nil
    end
  end

  def connected?
    !!@connection.try(:connected?)
  end

  def raw_publish(options)
    @exchange.publish(options[:payload], :key => options[:key], :persistent => true)
  end

  def exchange(channel, which)
    exchange_name = which == :pub ? Promiscuous::AMQP::PUB_EXCHANGE :
                                    Promiscuous::AMQP::SUB_EXCHANGE
    channel.exchange(exchange_name, :type => :topic, :durable => true)
  end

  def publish(options={})
    @connection_lock.synchronize do
      tag = @channel.next_publish_seq_no if options[:on_confirm]
      raw_publish(options)
      @callback_mapping[tag] = options[:on_confirm] if options[:on_confirm]
    end
  rescue Exception => e
    e = Promiscuous::Error::Publisher.new(e, :payload => options[:payload])
    Promiscuous.warn "[publish] #{e} #{e.backtrace.join("\n")}"
    Promiscuous::Config.error_notifier.try(:call, e)
  end

  def confirm_select(channel, &callback)
    channel.confirm_select(callback)
  end

  def on_confirm(tag, multiple, nack=false)
    if multiple
      cbs = @callback_mapping.keys
              .select { |k| k <= tag }
              .map    { |k| @callback_mapping.delete(k) }
      cbs.each(&:call) unless nack
    else
      cb = @callback_mapping.delete(tag)
      cb.try(:call) unless nack
    end
  end

  module Subscriber
    def subscribe(options={}, &block)
      queue_name    = options[:queue_name]
      bindings      = options[:bindings]
      Promiscuous::AMQP.ensure_connected

      @lock = Mutex.new
      @connection, @channel = Promiscuous::AMQP.backend.new_connection
      @channel.basic_qos(Promiscuous::Config.prefetch)
      exchange = Promiscuous::AMQP.backend.exchange(@channel, :sub)
      @queue = @channel.queue(queue_name, Promiscuous::Config.queue_options)
      bindings.each do |binding|
        @queue.bind(exchange, :routing_key => binding)
        Promiscuous.debug "[bind] #{queue_name} -> #{binding}"
      end

      @subscription = subscribe_queue(@queue, &block)
    end

    def subscribe_queue(queue, &block)
      queue.subscribe(:ack => true) do |delivery_info, metadata, payload|
        block.call(MetaData.new(self, delivery_info), payload)
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

    def ack_message(tag)
      @lock.synchronize { @channel.ack(tag) } if @channel
    end

    def recover
      @lock.synchronize { @channel.basic_recover(true) } if @channel
    end

    def disconnect
      @lock.synchronize { @connection.stop; @channel = nil }
    end
  end
end
