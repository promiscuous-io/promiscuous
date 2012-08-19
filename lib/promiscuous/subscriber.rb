module Promiscuous::Subscriber
  autoload :ActiveRecord, 'promiscuous/subscriber/active_record'
  autoload :AMQP,         'promiscuous/subscriber/amqp'
  autoload :Attributes,   'promiscuous/subscriber/attributes'
  autoload :Base,         'promiscuous/subscriber/base'
  autoload :CustomClass,  'promiscuous/subscriber/custom_class'
  autoload :Envelope,     'promiscuous/subscriber/envelope'
  autoload :Error,        'promiscuous/subscriber/error'
  autoload :Model,        'promiscuous/subscriber/model'
  autoload :Mongoid,      'promiscuous/subscriber/mongoid'
  autoload :Polymorphic,  'promiscuous/subscriber/polymorphic'
  autoload :Upsert,       'promiscuous/subscriber/upsert'

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
