class Replicable::Publisher
  class_attribute :binding, :model
  attr_accessor :instance, :operation

  def initialize(instance, operation)
    @instance = instance
    @operation = operation
  end

  def amqp_payload
    {
      :binding   => self.class.binding,
      :id        => instance.id,
      :operation => operation,
      :payload   => payload
    }.to_json
  end

  def payload
    raise "You need to implement payload"
  end

  def self.publish(options={})
    self.model = options[:model]
    self.binding = options[:to]
    serialize_klass = self

    self.model.class_eval do
      [:create, :update, :destroy].each do |operation|
        __send__("after_#{operation}", "publish_changes_#{operation}".to_sym)

        define_method "publish_changes_#{operation}" do |&block|
          serializer = serialize_klass.new(self, operation)

          Replicable::AMQP.publish(:key => serializer.binding,
                                   :payload => serializer.amqp_payload)
        end
      end
    end
  end
end
