module Promiscuous::Subscriber::Polymorphic
  extend ActiveSupport::Concern
  include Promiscuous::Subscriber::Envelope
  include Promiscuous::Common::ClassHelpers

  included do
    class_attribute :polymorphic_map
    use_option :from_type
  end

  module ClassMethods
    def from_type
      super ? super : guess_class_name('Subscribers')
    end

    def from_type=(value)
      super
      setup_polymorphic_mapping
    end

    def setup_polymorphic_mapping
      self.polymorphic_map ||= {}
      polymorphic_map[from_type.to_s] = self if from_type
    end

    def inherited(subclass)
      super
      subclass.setup_polymorphic_mapping unless options.has_key?(:class)
    end

    def polymorphic_subscriber_from(payload)
      type = payload.is_a?(Hash) ? payload['type'] : nil
      polymorphic_map[type] || self
    end
  end
end
