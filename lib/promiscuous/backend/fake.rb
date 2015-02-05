class Promiscuous::Backend::Fake
  attr_accessor :messages

  class << self
    def backend
      Promiscuous::Backend.driver
    end
    delegate :num_messages, :get_next_message, :get_next_payload, :to => :backend
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
    Promiscuous.debug "[publish (fake)] #{options[:exchange] || "default"}/#{options[:key]} #{options[:payload]}"
    @messages << options
    options[:on_confirm].try(:call)
  end

  def num_messages
    @messages.count
  end

  def get_next_message
    @messages.shift
  end

  def get_next_payload
    msg = get_next_message
    msg && JSON.parse(msg[:payload])
  end

  module Subscriber
    def subscribe(options={}, &block)
    end

    def fetch_and_process_messages(&block)
    end

    def disconnect
    end

    def delete_queues
    end
  end
end
