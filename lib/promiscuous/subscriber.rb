module Promiscuous::Subscriber
  require 'promiscuous/subscriber/error'
  require 'promiscuous/subscriber/mongoid'
  require 'promiscuous/subscriber/amqp'

  def self.process(payload, options={})
    subscriber = Promiscuous::Subscriber::AMQP.subscriber_for(payload)
    return payload if subscriber.nil?

    sub = subscriber.new(options.merge(:payload => payload))
    sub.process if sub.respond_to?(:process)
    sub.instance
  end
end
