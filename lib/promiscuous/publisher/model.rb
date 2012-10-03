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
    hook_callbacks if published
  end

  module ClassMethods
    def publish(options)
      super
      hook_callbacks
    end

    def hook_callbacks
      klass.class_eval do
        cattr_accessor :publisher_operation_hooked
        return if self.publisher_operation_hooked
        self.publisher_operation_hooked = true

        [:create, :update, :destroy].each do |operation|
          __send__("after_#{operation}", "promiscuous_publish_#{operation}".to_sym)
          define_method "promiscuous_publish_#{operation}" do
            self.class.promiscuous_publisher.new(:instance => self, :operation => operation).publish
          end
        end
        alias :promiscuous_sync :promiscuous_publish_update
      end
    end
  end
end
