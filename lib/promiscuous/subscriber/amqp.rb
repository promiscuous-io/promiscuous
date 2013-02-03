module Promiscuous::Subscriber::AMQP
  extend ActiveSupport::Concern
  include Promiscuous::Subscriber::Envelope

  mattr_accessor :subscribers
  self.subscribers = {}

  def self.subscriber_from(payload)
    if key = payload.is_a?(Hash) ? payload['__amqp__'] : nil
      sub = self.subscribers[key]
      sub ||= Promiscuous::Subscriber::Dummy
    end
  end

  included { use_option :from }

  module ClassMethods
    def from=(_)
      super
      old_sub = Promiscuous::Subscriber::AMQP.subscribers[from]
      raise "The subscriber '#{old_sub}' already listen on '#{from}'" if old_sub
      Promiscuous::Subscriber::AMQP.subscribers[from] = self
    end
  end
end
