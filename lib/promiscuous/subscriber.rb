module Promiscuous::Subscriber
  autoload :ActiveRecord, 'promiscuous/subscriber/active_record'
  autoload :Mongoid,      'promiscuous/subscriber/mongoid'
  autoload :Error,        'promiscuous/subscriber/error'

  def self.get_subscriber_from(payload)
    sub = AMQP.subscriber_from(payload)
    if sub && defined?(Polymorphic) && sub.include?(Polymorphic)
      sub = sub.polymorphic_subscriber_from(payload)
    end
    sub || Base
  end

  def self.process(payload, options={})
    subscriber_klass = self.get_subscriber_from(payload)

    sub = subscriber_klass.new(options.merge(:payload => payload))
    sub.process
    sub.instance
  end
end
