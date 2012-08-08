module Replicable::Subscriber
  require 'replicable/subscriber/mongoid'
  require 'replicable/subscriber/amqp'

  def self.process(payload, options={})
    subscriber = Replicable::Subscriber::AMQP.subscriber(payload)
    return payload if subscriber.nil?

    sub = subscriber.new(options.merge(:payload => payload))
    sub.process if sub.respond_to?(:process)
    sub.instance
  end
end
