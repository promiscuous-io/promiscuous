module Promiscuous::Subscriber::Attributes
  extend ActiveSupport::Concern

  def process
    super
    return unless process_attributes?

    self.class.attributes.each do |attr|
      attr = attr.to_s
      unless payload.has_key?(attr)
        raise "Attribute '#{attr}' is missing from the payload"
      end

      value = payload[attr]
      old_value = instance.__send__(attr)
      new_value = Promiscuous::Subscriber.process(payload[attr], :old_value => old_value)
      instance.__send__("#{attr}=", new_value) if old_value != new_value
    end
  end

  def process_attributes?
    true
  end

  included { use_option :attributes }

  module ClassMethods
    def attributes=(value)
      super(superclass.attributes.to_a + value)
    end
  end
end
