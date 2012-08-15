module Promiscuous::Subscriber
  autoload :ActiveRecord, 'promiscuous/subscriber/active_record'
  autoload :Mongoid,      'promiscuous/subscriber/mongoid'
  autoload :Error,        'promiscuous/subscriber/error'
  autoload :AMQP,         'promiscuous/subscriber/amqp'

  mattr_accessor :subscribers
  self.subscribers = {}

  def self.bind(key, subscriber)
    if self.subscribers.has_key?(key)
      raise "The subscriber '#{self.subscribers[key]}' already listen on '#{key}'"
    end
    self.subscribers[key] = subscriber
  end

  def self.get_subscriber(payload, options={})
    key = Promiscuous::Subscriber::AMQP.subscriber_key(payload)

    if key
      raise "FATAL: Unknown binding: '#{key}'" unless self.subscribers.has_key?(key)
      self.subscribers[key]
    else
      Promiscuous::Subscriber::Base
    end
  end

  def self.process(payload, options={})
    subscriber_klass = get_subscriber(payload)

    sub = subscriber_klass.new(options.merge(:payload => payload))
    sub.process
    sub.instance
  end
end
