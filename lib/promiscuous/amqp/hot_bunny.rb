class Promiscuous::AMQP::HotBunny
  attr_accessor :connection

  def initialize
    require 'hot_bunnies'
  end

  def connect
    @connection = HotBunnies.connect(:uri => Promiscuous::Config.amqp_url,
                                     :heartbeat_interval => Promiscuous::Config.heartbeat)

    @pub_channel = @connection.create_channel
    @pub_exchange = exchange(@pub_channel, :pub)
  end

  def disconnect
    @connection.close
  end

  def connected?
    @connection.is_open
  end

  def publish(options={})
    @master_exchange.publish(options[:payload], :routing_key => options[:key], :persistent => true)
  end

  def exchange(channel, which)
    exchange_name = which == :pub ? Promiscuous::AMQP::PUB_EXCHANGE :
                                    Promiscuous::AMQP::SUB_EXCHANGE
    channel.exchange(exchange_name, :type => :topic, :durable => true)
  end

  module CelluloidSubscriber
    def subscribe(options={}, &block)
      queue_name    = options[:queue_name]
      bindings      = options[:bindings]
      Promiscuous::AMQP.ensure_connected

      @channel = Promiscuous::AMQP::backend.connection.create_channel
      @channel.prefetch = Promiscuous::Config.prefetch
      exchange = Promiscuous::AMQP::backend.exchange(@channel, :sub)
      queue = @channel.queue(queue_name, Promiscuous::Config.queue_options)
      bindings.each do |binding|
        queue.bind(exchange, :routing_key => binding)
        Promiscuous.debug "[bind] #{queue_name} -> #{binding}"
      end
      @subscription = queue.subscribe(:ack => true, :blocking => false, &block)
    end

    def wait_for_subscription
      # Nothing to do, things are synchronous.
    end

    def disconnect
      begin
        @subscription.cancel
      rescue
        sleep 0.1
        retry
      end
      @channel.close
    end

    def recover
    end
  end
end
