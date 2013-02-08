require 'eventmachine'

class Promiscuous::Subscriber::Worker::Pump
  include Celluloid

  attr_accessor :subscribe_sync

  def initialize
    # We need to subscribe to everything to keep up with the version tracking
    queue_name = "#{Promiscuous::Config.app}.promiscuous"
    bindings = ['*']

    unless Promiscuous::Config.backend == :rubyamqp
      raise "you must use the ruby_amqp backend"
    end
    Promiscuous::AMQP.ensure_connected

    @subscribe_sync = Promiscuous::AMQP::RubyAMQP::Synchronizer.new
    Promiscuous::AMQP::RubyAMQP.get_channel(:pump) do |channel|
      @channel = channel
      # TODO channel.on_error ?

      queue = channel.queue(queue_name, Promiscuous::Config.queue_options)
      exchange = Promiscuous::AMQP::RubyAMQP.get_exchange(:pump)
      bindings.each do |binding|
        queue.bind(exchange, :routing_key => binding)
        Promiscuous.debug "[bind] #{queue_name} -> #{binding}"
      end
      queue.subscribe(:ack => true, :confirm => proc { @subscribe_sync.signal }, &method(:process_payload))
    end
    @subscribe_sync.wait
  end

  def finalize
    channel_sync = Promiscuous::AMQP::RubyAMQP::Synchronizer.new
    Promiscuous::AMQP::RubyAMQP.close_channel(:pump) do
      channel_sync.signal
    end
    channel_sync.wait
  end

  def recover
    EM.next_tick { @channel.recover }
  end

  def process_payload(metadata, payload)
    msg = Promiscuous::Subscriber::Worker::Message.new(metadata, payload)
    Celluloid::Actor[:message_synchronizer].process_when_ready(msg)
  end
end
