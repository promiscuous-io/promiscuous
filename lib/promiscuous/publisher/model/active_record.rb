module Promiscuous::Publisher::Model::ActiveRecord
  extend ActiveSupport::Concern

  module ModelInstanceMethods
    extend ActiveSupport::Concern

    def with_promiscuous(options={}, &block)
      fetch_proc = proc { self.class.find(self.id) }
      self.class.promiscuous_publisher.new(options.merge(:instance => self, :fetch_proc => fetch_proc)).commit(&block)
    end

    included do
      around_create  { |&block| with_promiscuous(:operation => :create,  &block) }
      around_update  { |&block| with_promiscuous(:operation => :update,  &block) }
      around_destroy { |&block| with_promiscuous(:operation => :destroy, &block) }
    end
  end

  module ClassMethods
    def setup_class_binding
      super
      klass.__send__(:include, ModelInstanceMethods) if klass
    end
  end
end
