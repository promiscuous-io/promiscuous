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

  module ClassMethods
    def setup_class_binding
      super
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

        def promiscuous_sync(options={})
          options = options.merge({ :instance => self, :operation => :update, :defer => false })
          self.class.promiscuous_publisher.new(options).publish
          true
        end
      end if klass
    end
  end
end
