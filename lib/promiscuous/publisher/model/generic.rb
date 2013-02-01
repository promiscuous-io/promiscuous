module Promiscuous::Publisher::Model::Generic
  extend ActiveSupport::Concern

  module ModelInstanceMethods
    extend ActiveSupport::Concern

    def with_promiscuous(options={}, &block)
      publisher = self.class.promiscuous_publisher.new(options.merge(:instance => self))
      ret = publisher.commit_db(&block)
      # FIXME if we die here, we are out of sync
      publisher.publish
      ret
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

      if klass && !klass.include?(ModelInstanceMethods)
        klass.__send__(:include, ModelInstanceMethods)
        Promiscuous::Publisher::Model.klasses << klass
      end
    end
  end
end
