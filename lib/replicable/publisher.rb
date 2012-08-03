class Replicable::Publisher
  class_attribute :app_name, :model
  attr_accessor :instance, :operation

  def initialize(instance, operation)
    @instance = instance
    @operation = operation
  end

  def amqp_key
    path = [self.class.app_name]
    path << self.class.model.to_s.underscore
    path.join('.')
  end

  def amqp_payload
    {
      :id        => instance.id,
      :operation => operation,
      :classes   => [model.to_s.underscore],
      :payload   => payload
    }.to_json
  end

  def payload
    raise "You need to implement payload"
  end

  def self.publish(model_name, options={})
    self.model = model_name.to_s.camelize.constantize
    self.app_name = options[:app_name]
    serialize_klass = self

    self.model.class_eval do
      [:create, :update, :destroy].each do |operation|
        __send__("after_#{operation}", "publish_changes_#{operation}".to_sym)

        define_method "publish_changes_#{operation}" do |&block|
          serializer = serialize_klass.new(self, operation)

          Replicable::AMQP.publish(:key => serializer.amqp_key,
                                   :payload => serializer.amqp_payload)
        end
      end
    end
  end
end
