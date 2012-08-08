module Replicable::Publisher::Attributes
  extend ActiveSupport::Concern

  def payload
    return nil unless include_attributes?

    Hash[attributes.map do |field|
      optional = field.to_s[-1] == '?'
      field = field.to_s[0...-1].to_sym if optional
      [field, payload_for(field)] if !optional || instance.respond_to?(field)
    end]
  end

  def payload_for(field)
    value = instance.__send__(field)
    if value.class.respond_to?(:replicable_publisher)
      value.class.replicable_publisher.new(options.merge(:instance => value)).payload
    else
      value
    end
  end

  def include_attributes?
    true
  end

  included { use_option :attributes }
end
