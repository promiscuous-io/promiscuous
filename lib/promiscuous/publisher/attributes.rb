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
    def publish(options)
      if self.options[:attributes] and options[:attributes]
        options = options.dup
        options[:attributes] = (self.options[:attributes] + options[:attributes]).uniq
      end

      super(options)
    end
  end
end
