require 'promiscuous/subscriber/envelope'

module Promiscuous::Subscriber::Polymorphic
  extend ActiveSupport::Concern
  include Promiscuous::Subscriber::Envelope

  def klass
    klass = (subscribe_options[:classes] || {})[type]
    klass.nil? ? super : klass
  end

  included { use_payload_attribute :type }
end
