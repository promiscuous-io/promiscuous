module Promiscuous::Publisher::Mongoid::Embedded
  extend ActiveSupport::Concern

  def payload
    if instance.is_a?(Array)
      Promiscuous::Publisher::Mongoid::EmbeddedMany.new(:instance => instance).payload
    else
      super.merge(:id => instance.id)
    end
  end

  included do
    klass.class_eval do
      callback = proc do
        if _parent.respond_to?(:with_promiscuous)
          _parent.save
          # XXX FIXME mongoid needs help, and we need to deal with that.
          # We'll address that once we hook on moped
        end
      end

      after_create callback
      after_update callback
      after_destroy callback
    end
  end
end
