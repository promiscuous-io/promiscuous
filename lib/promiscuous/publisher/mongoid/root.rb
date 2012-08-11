module Promiscuous::Publisher::Mongoid::Root
  extend ActiveSupport::Concern

  def operation
    options[:operation]
  end

  def payload
    super.merge(:id => instance.id, :operation => operation)
  end

  def include_attributes?
    operation != :destroy
  end

  module ClassMethods
    def publish(options)
      super

      options[:class].class_eval do
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
