module Promiscuous::AMQP::Fake
  mattr_accessor :messages

  def self.connect
    @messages = []
  end

  def self.disconnect
    @messages = []
  end

  def self.connected?
    true
  end

  def self.publish(options={})
    @messages << options
  end

  def self.get_next_message
    @messages.shift
  end

  def self.get_next_payload
    JSON.parse(get_next_message[:payload])
  end

  def self.open_queue(options={}, &block)
  end

  module CelluloidSubscriber
    def subscribe(options={}, &block)
    end

    def wait_for_subscription
    end

    def finalize
    end

    def recover
    end
  end
end
