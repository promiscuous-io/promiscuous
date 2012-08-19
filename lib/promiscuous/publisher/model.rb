require 'promiscuous/publisher/envelope'

module Promiscuous::Publisher::Model
  extend ActiveSupport::Concern
  include Promiscuous::Publisher::Envelope

  def operation
    options[:operation]
  end

  def payload
    super.merge(:id => instance.id, :operation => operation)
  end

  def include_attributes?
    operation != :destroy
  end

  included do
    publish(options) if initialized
  end

  module ClassMethods
    def publish(options)
      super unless initialized

      klass.class_eval do
        [:create, :update, :destroy].each do |operation|
          __send__("after_#{operation}", "promiscuous_publish_#{operation}".to_sym)

          define_method "promiscuous_publish_#{operation}" do
            self.class.promiscuous_publisher.new(:instance => self, :operation => operation).amqp_publish
          end
        end
      end
    end
  end
end

