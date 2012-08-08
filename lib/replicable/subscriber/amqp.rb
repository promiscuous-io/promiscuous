require 'replicable/subscriber/envelope'

module Replicable::Subscriber::AMQP
  extend ActiveSupport::Concern

  mattr_accessor :subscribers
  self.subscribers = {}

  def self.subscriber_for(payload)
    origin = payload.is_a?(Hash) ? payload['__amqp__'] : nil
    if origin
      unless subscribers.has_key?(origin)
        raise "FATAL: Unknown binding: '#{origin}'"
      end
      subscribers[origin]
    end
  end

  module ClassMethods
    def subscribe(options)
      super

      subscribers = Replicable::Subscriber::AMQP.subscribers
      from = options[:from]

      if subscribers.has_key?(from)
        raise "The subscriber '#{subscribers[from]}' already listen on '#{from}'"
      end
      subscribers[from] = self
    end
  end
end
