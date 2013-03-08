class Promiscuous::AMQP::Fake
  attr_accessor :messages

  class << self
    def backend
      Promiscuous::AMQP.backend
    end
    delegate :get_next_message, :get_next_payload, :to => :backend
  end

  def connect
    @messages = []
  end

  def disconnect
  end

  def connected?
    true
  end

  def publish(options={})
    @messages << options
  end

  def get_next_message
    @messages.shift
  end

  def get_next_payload
    JSON.parse(get_next_message[:payload])
  end

  def open_queue(options={}, &block)
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
