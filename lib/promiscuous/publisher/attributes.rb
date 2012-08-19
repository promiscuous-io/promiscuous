module Promiscuous::Publisher::Attributes
  extend ActiveSupport::Concern

  def payload
    return nil unless include_attributes?

    Hash[attributes.map { |field| [field, payload_for(field)] }]
  end

  def payload_for(field)
    value = instance.__send__(field)
    if value.class.respond_to?(:promiscuous_publisher)
      value.class.promiscuous_publisher.new(options.merge(:instance => value)).payload
    else
      value
    end
  end

  def include_attributes?
    true
  end

  included { use_option :attributes }

  module ClassMethods
    def attributes=(value)
      super(superclass.attributes.to_a + value)
    end
  end
end
