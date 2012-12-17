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

      options = {}
      options[:parent]    = instance
      options[:old_value] = instance.__send__(attr) if instance.respond_to?(attr)
      sub = Promiscuous::Subscriber.subscriber_for(payload[attr], options)

      sub.process
      instance.__send__("#{attr}=", sub.instance) if sub.should_update_parent?
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
