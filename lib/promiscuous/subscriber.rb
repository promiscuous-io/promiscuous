module Promiscuous::Subscriber
  autoload :ActiveRecord, 'promiscuous/subscriber/active_record'
  autoload :AMQP,         'promiscuous/subscriber/amqp'
  autoload :Attributes,   'promiscuous/subscriber/attributes'
  autoload :Base,         'promiscuous/subscriber/base'
  autoload :Class,        'promiscuous/subscriber/class'
  autoload :Envelope,     'promiscuous/subscriber/envelope'
  autoload :Error,        'promiscuous/subscriber/error'
  autoload :Lint,         'promiscuous/subscriber/lint'
  autoload :Model,        'promiscuous/subscriber/model'
  autoload :Mongoid,      'promiscuous/subscriber/mongoid'
  autoload :Polymorphic,  'promiscuous/subscriber/polymorphic'
  autoload :Upsert,       'promiscuous/subscriber/upsert'
  autoload :Observer,     'promiscuous/subscriber/observer'
  autoload :Worker,       'promiscuous/subscriber/worker'

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
