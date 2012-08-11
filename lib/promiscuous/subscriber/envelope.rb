module Promiscuous::Subscriber::Envelope
  extend ActiveSupport::Concern

  module ClassMethods
    def use_payload_attribute(attr, options={})
      define_method(attr) do
        value = payload_with_envelope[attr.to_s]
        value = value.to_sym if options[:symbolize]
        value
      end
    end
  end

  included do
    alias_method :payload_with_envelope, :payload
    use_payload_attribute :payload
  end
end
