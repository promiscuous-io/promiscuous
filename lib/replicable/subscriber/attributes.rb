module Replicable::Subscriber::Attributes
  extend ActiveSupport::Concern

  def process
    super
    return unless process_attributes?

    attributes.each do |attr|
      attr = attr.to_s
      optional = attr[-1] == '?'
      attr = attr[0...-1] if optional
      setter = "#{attr}="

      if payload.has_key?(attr)
        value = payload[attr]
        old_value = instance.__send__(attr)
        new_value = Replicable::Subscriber.process(payload[attr], :old_value => old_value)
        instance.__send__(setter, new_value) if old_value != new_value
      else
        raise "Unknown attribute '#{attr}'" unless optional
      end
    end
  end

  def process_attributes?
    true
  end

  module ClassMethods
    def subscribe(options)
      super
      use_option :attributes
    end
  end
end
