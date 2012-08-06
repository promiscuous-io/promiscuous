class Replicable::Subscriber
  mattr_accessor :subscriptions
  self.subscriptions = Set.new

  class_attribute :binding, :model
  attr_accessor :instance, :operation, :type

  def self.subscribe(options={})
    self.model = options[:model]
    self.binding = options[:from]

    Replicable::Subscriber.subscriptions << self
  end
end
