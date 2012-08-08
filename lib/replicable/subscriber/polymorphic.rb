require 'replicable/subscriber/envelope'

module Replicable::Subscriber::Polymorphic
  extend ActiveSupport::Concern
  include Replicable::Subscriber::Envelope

  def klass
    klass = (subscribe_options[:classes] || {})[type]
    klass.nil? ? super : klass
  end

  included { use_payload_attribute :type }
end
