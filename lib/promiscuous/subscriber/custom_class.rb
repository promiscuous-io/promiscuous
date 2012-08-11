require 'promiscuous/subscriber/envelope'

module Promiscuous::Subscriber::CustomClass
  extend ActiveSupport::Concern

  def klass
    unless subscribe_options[:class]
      raise "I don't want to be rude or anything, "
            "but have you defined the class to deserialize?"
    end
    subscribe_options[:class]
  end

  def instance
    @instance ||= fetch
  end
end
