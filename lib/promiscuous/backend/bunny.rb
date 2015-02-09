class Promiscuous::Backend::Bunny
  def self.hijack_bunny
    return if @bunny_hijacked
    ::Bunny::Session.class_eval do
      alias_method :handle_network_failure_without_promiscuous, :handle_network_failure

      def handle_network_failure(e)
        Promiscuous.warn "[amqp] #{e}. Reconnecting..."
        Promiscuous::Config.error_notifier.call(e)
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

  def raw_new_connection(options={})
    connection = ::Bunny.new(options[:url], :heartbeat_interval => Promiscuous::Config.heartbeat,
                                            :socket_timeout     => Promiscuous::Config.socket_timeout,
                                            :connect_timeout    => Promiscuous::Config.socket_timeout)
    connection.start
    connection
  end

  def raw_confirm_select(channel, &callback)
    channel.confirm_select(callback)
  end

  def new_connection(options={})
    connection = raw_new_connection(options)
    channel = connection.create_channel
    channel.basic_qos(options[:prefetch]) if options[:prefetch]
    raw_confirm_select(channel, &method(:on_confirm)) if options[:confirm]

    exchanges = {}
    options[:exchanges].each do |exchange_name|
      exchanges[exchange_name] = channel.exchange(exchange_name, :type => :topic, :durable => true)
    end
    [connection, channel, exchanges]
  end

  def connect
    connection_options = { :url       => Promiscuous::Config.publisher_amqp_url,
                           :exchanges => [Promiscuous::Config.publisher_exchange,
                                          Promiscuous::Config.sync_exchange],
                           :confirm   => true }
    @connection, @channel, @exchanges = new_connection(connection_options)
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
    @exchanges[options[:exchange]].publish(options[:payload], :key => options[:key], :persistent => true)
  end

  def publish(options={})
    raise "Exchange '#{options[:exchange]}' not one of: #{@exchanges.keys}" unless @exchanges[options[:exchange]]

    Promiscuous.debug "[publish] #{options[:exchange]}/#{options[:key]} #{options[:payload]}"

    @connection_lock.synchronize do
      if options[:async]
        tag = @channel.next_publish_seq_no if options[:on_confirm]
        @callback_mapping[tag] = options[:on_confirm] if options[:on_confirm]
      end

      raw_publish(options)

      unless options[:async]
        if @channel.wait_for_confirms
          options[:on_confirm].call if options[:on_confirm]
        else
          raise Promiscuous::Error::PublishUnacknowledged.new(options[:payload])
        end
      end
    end
  rescue Exception => e
    Promiscuous.warn("[publish] Failure publishing to rabbit #{e}\n#{e.backtrace.join("\n")}")
    e = Promiscuous::Error::Publisher.new(e, :payload => options[:payload])

    if options[:async]
      Promiscuous::Config.error_notifier.call(e)
    else
      raise e
    end
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

  def process_message(message)
    begin
      Promiscuous::Subscriber::UnitOfWork.process(message)
    rescue Exception => e
      Promiscuous::Config.error_notifier.call(e)
      raise e if Promiscuous::Config.test_mode
      message.nack
    end
  end

  module Subscriber
    def subscribe(options={}, &block)
      @lock = Mutex.new
      @prefetch = Promiscuous::Config.prefetch

      configure_rabbit

      connection_options = { :url       => Promiscuous::Config.subscriber_amqp_url,
                             :exchanges => options[:bindings].keys,
                             :prefetch  => @prefetch }
      @connection, @channel, exchanges = Promiscuous::Backend.new_connection(connection_options)

      create_queues(@channel)

      # Main queue binding
      exchanges.keys.zip(options[:bindings].values).each do |exchange, bindings|
        bindings.each do |binding|
          @queue.bind(exchange, :routing_key => binding)
          Promiscuous.debug "[bind] #{exchange}/#{binding}/#{Promiscuous::Config.queue_name}"
        end
      end

      # Error queue binding
      @error_queue.bind(Promiscuous::Config.error_exchange, :routing_key => Promiscuous::Config.error_routing)

      @subscription = subscribe_queue(@queue, &block)
    end

    def configure_rabbit
      policy = {
        "dead-letter-routing-key" => Promiscuous::Config.error_routing,
        "dead-letter-exchange"    => Promiscuous::Config.error_exchange
      }.merge(Promiscuous::Config.queue_policy)

      Promiscuous::Rabbit::Policy.set Promiscuous::Config.queue_name,
        {
        "pattern"    => Promiscuous::Config.queue_name,
        "apply-to"   => "queues",
        "definition" => policy
        }

     policy = {
       "message-ttl" => Promiscuous::Config.error_ttl,
       "dead-letter-routing-key" => Promiscuous::Config.retry_routing,
       "dead-letter-exchange" => Promiscuous::Config.error_exchange
     }.merge(Promiscuous::Config.queue_policy)
     Promiscuous::Rabbit::Policy.set Promiscuous::Config.error_queue_name,
       {
       "pattern"     => Promiscuous::Config.error_queue_name,
       "apply-to"    => "queues",
       "definition"  => policy
       }
    end

    def subscribe_queue(queue, &block)
      queue.subscribe(:manual_ack => true) do |delivery_info, metadata, payload|
        block.call(MetaData.new(self, delivery_info), payload)
      end
    end

    def create_queues(channel)
      @queue       = channel.queue(Promiscuous::Config.queue_name,
                                   Promiscuous::Config.queue_options)

      @error_queue = channel.queue(Promiscuous::Config.error_queue_name,
                                   Promiscuous::Config.queue_options)
    end

    def delete_queues
      [@error_queue, @queue].each { |queue| queue.try(:delete) }
    end

    class MetaData
      def initialize(subscriber, delivery_info)
        @subscriber = subscriber
        @delivery_info = delivery_info
      end

      def ack
        @subscriber.ack_message(@delivery_info.delivery_tag)
      end

      def nack
        @subscriber.nack_message(@delivery_info.delivery_tag)
      end
    end

    module Worker
      def backend_subscriber_initialize(subscriber_worker)
        @pump = Promiscuous::Subscriber::Worker::Pump.new(subscriber_worker)
        @runner = Promiscuous::Subscriber::Worker::Runner.new(subscriber_worker)
      end

      def backend_subscriber_start
        @pump.connect
        @runner.start
      end

      def backend_subscriber_stop
        @runner.stop
        @pump.disconnect
      end

      def backend_subscriber_show_stop_status(num_show_stop_requests)
        @runner.show_stop_status(num_show_stop_requests)
      end
    end

    def ack_message(tag)
      @lock.synchronize { @channel.ack(tag) } if @channel
    end

    def nack_message(tag)
      @lock.synchronize { @channel.nack(tag) } if @channel
    end

    def recover
      @lock.synchronize { @channel.basic_recover(true) } if @channel
    end

    def disconnect
      @lock.synchronize { @connection.stop; @channel = nil }
    end
  end
end
