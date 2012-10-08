module Promiscuous::Subscriber::Mongoid::Embedded
  extend ActiveSupport::Concern

  def fetch
    instance = old_value.nil? ? klass.new : old_value
    instance.id = id
    instance
  end

  def old_value
    options[:old_value]
  end

  included { use_payload_attribute :id }
end
