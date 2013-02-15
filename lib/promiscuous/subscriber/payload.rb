class Promiscuous::Subscriber::Payload
  attr_accessor :message, :id, :operation, :attributes, :model

  def initialize(payload, message=nil)
    self.message = message

    if payload.is_a?(Hash) && payload['__amqp__']
      self.id         = payload['id']
      self.operation  = payload['operation'].try(:to_sym)
      self.attributes = payload['payload'] # TODO payload payload... not great.
      self.model      = self.class.get_subscribed_model(payload)
    end
  end

  def self.get_subscribed_model(payload)
    # TODO test the regexp source
    mapping = Promiscuous::Subscriber::Model.mapping
    model = mapping.select { |from| payload['__amqp__'] =~ from }.values.first
    model = get_subscribed_subclass(model, payload) if model
    model
  end

  def self.get_subscribed_subclass(root_model, payload)
    # TODO remove 'type' (backward compatibility)
    received_ancestors = [payload['ancestors'] || payload['type']].flatten.compact
    # TODO test the ancestor chain
    subscriber_subclasses = [root_model] + root_model.descendants
    received_ancestors.each do |ancestor|
      model = subscriber_subclasses.select { |klass| klass.subscribe_as == ancestor }.first
      return model if model
    end
    root_model
  end
end
