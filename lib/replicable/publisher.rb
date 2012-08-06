class Replicable::Publisher
  class_attribute :amqp_binding, :model, :attributes
  attr_accessor :instance, :operation

  def initialize(instance, operation)
    @instance = instance
    @operation = operation
  end

  def amqp_payload
    {
      :__amqp_binding__  => self.class.amqp_binding,
      :id        => instance.id,
      :operation => operation,
      :type      => instance.class.to_s,
      :payload   => payload
    }
  end

  def payload
    payload = {}
    if self.class.attributes
      self.class.attributes.each do |field|
        optional = field.to_s[-1] == '?'
        field = field.to_s[0...-1].to_sym if optional

        if !optional or instance.respond_to?(field)
          value = instance.__send__(field)
          if value.class.respond_to?(:replicable_publisher)
            value = value.class.replicable_publisher.new(value, operation).amqp_payload
          end
          payload[field] = value
        end
      end
    else
      raise "I don't know how to build your payload"
    end
    payload
  end

  def self.publish(options={})
    self.amqp_binding = options[:to]
    self.model        = options[:model]
    self.attributes   = options[:attributes]

    publisher_class = self
    self.model.class_eval do
      class_attribute :replicable_publisher
      self.replicable_publisher = publisher_class

      [:create, :update, :destroy].each do |operation|
        __send__("after_#{operation}", "publish_changes_#{operation}".to_sym)

        define_method "publish_changes_#{operation}" do
          if embedded?
            _parent.save
            _parent.reload # mongoid is a bit retarded, so we need to reload here.
            _parent.publish_changes_update
          else
            publisher = self.class.replicable_publisher.new(self, operation)

            Replicable::AMQP.publish(:key => publisher.amqp_binding,
                                     :payload => publisher.amqp_payload.to_json)
          end
        end
      end
    end
  end
end
