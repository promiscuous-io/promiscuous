module Promiscuous::Publisher::Mongoid::DeferEmbedded
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
        if _parent.respond_to?(:promiscuous_publish_update)
          _parent.promiscuous_publish_update
        end
      end

      before_create callback
      before_update callback
      before_destroy callback
    end
  end
end
