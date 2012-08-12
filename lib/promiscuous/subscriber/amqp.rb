require 'promiscuous/subscriber/envelope'

module Promiscuous::Subscriber::AMQP
  extend ActiveSupport::Concern

  def self.subscriber_key(payload)
    payload.is_a?(Hash) ? payload['__amqp__'] : nil
  end

  module ClassMethods
    def subscribe(options)
      super
      Promiscuous::Subscriber.bind(options[:from], self)
    end
  end
end
