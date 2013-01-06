module Promiscuous::Subscriber
  extend Promiscuous::Autoload
  autoload :ActiveRecord, :AMQP, :Attributes, :Base, :Class, :Envelope, :Error,
           :Lint, :Model, :Mongoid, :Polymorphic, :Upsert, :Observer, :Worker

  def self.lint(*args)
    Lint.lint(*args)
  end

  def self.subscriber_class_for(payload)
    sub = AMQP.subscriber_from(payload)
    if sub && defined?(Polymorphic) && sub.include?(Polymorphic)
      sub = sub.polymorphic_subscriber_from(payload)
    end
    sub || Base
  end

  def self.subscriber_for(payload, options={})
    self.subscriber_class_for(payload).new(options.merge(:payload => payload))
  end

  def self.process(payload, options={})
    sub = self.subscriber_for(payload, options)
    sub.process
    sub.instance
  end
end
