require 'promiscuous/publisher/envelope'

module Promiscuous::Publisher::Polymorphic
  extend ActiveSupport::Concern
  include Promiscuous::Publisher::Envelope

  def payload
    super.merge(:type => instance.class.to_s)
  end

  module ClassMethods
    def publish(options)
      super
      self.descendants.each { |subclass| inherited(subclass) }
    end

    def inherited(subclass)
      super
      subclass.publish(options.merge(:inherited => true)) if published
    end
  end
end
