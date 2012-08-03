class Replicable::Subscriber
  mattr_accessor :subscriptions
  self.subscriptions = Set.new

  class_attribute :from_app, :from_class, :model
  attr_accessor :instance, :operation

  def initialize(instance, operation)
    @instance = instance
    @operation = operation
  end

  def self.subscribe(model_name, options={})
    self.model = model_name.to_s.camelize.constantize
    self.from_app = options[:from].split('/')[0]
    self.from_class = options[:from].split('/')[1..-1].join('')

    Replicable::Subscriber.subscriptions << self
  end

  def self.amqp_binding
    "#{from_app}.#{from_class}"
  end
end
