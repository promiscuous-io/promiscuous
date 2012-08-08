require 'replicable/subscriber/envelope'

module Replicable::Subscriber::Polymorphic
  extend ActiveSupport::Concern
  include Replicable::Subscriber::Envelope

  def klass
    klass = subscribe_options[:classes].try(:[], type)
    klass.nil? ? super : klass
  end

  module ClassMethods
    def subscribe(options)
      super
      use_payload_attribute :type
    end
  end
end
