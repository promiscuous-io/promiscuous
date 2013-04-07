class Promiscuous::AMQP::HotBunnies < Promiscuous::AMQP::Bunny
  attr_accessor :connection

  def initialize_driver
    require 'hot_bunnies'
  end

  # TODO auto reconnect

  def raw_new_connection(options={})
    ::HotBunnies.connect(:uri => options[:url],
                         :heartbeat_interval => Promiscuous::Config.heartbeat,
                         :connection_timeout => Promiscuous::Config.socket_timeout)
  end

  def raw_confirm_select(channel, &callback)
    channel.add_confirm_listener(&callback)
    channel.confirm_select
  end

  def raw_publish(options={})
    options[:exchange].publish(options[:payload], :routing_key => options[:key], :persistent => true)
  end

  def disconnect
    @connection_lock.synchronize do
      return unless connected?
      @channel.close rescue nil
      @connection.close rescue nil
      @connection = @channel = nil
    end
  end

  def connected?
    !!@connection.try(:is_open)
  end

  module Subscriber
    include Promiscuous::AMQP::Bunny::Subscriber

    def subscribe_queue(queue, &block)
      queue.subscribe(:ack => true, :blocking => false, &block)
    end

    def disconnect
      @lock.synchronize do
        @channel = nil
        @subscription.shutdown! rescue nil
        @connection.close rescue nil
      end
    end
  end
end
