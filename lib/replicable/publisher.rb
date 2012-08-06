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
      :type      => instance.class.to_s,
      :payload   => payload
    }.to_json
  end

  def payload
    raise "You need to implement payload"
  end

  def self.publish(options={})
    self.model = options[:model]
    self.binding = options[:to]
    publisher_class = self

    self.model.class_eval do
      [:create, :update, :destroy].each do |operation|
        __send__("after_#{operation}", "publish_changes_#{operation}".to_sym)

        define_method "publish_changes_#{operation}" do |&block|
          publisher = publisher_class.new(self, operation)

          Replicable::AMQP.publish(:key => publisher.binding,
                                   :payload => publisher.amqp_payload)
        end
      end
    end
  end
end
