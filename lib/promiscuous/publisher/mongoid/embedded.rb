module Promiscuous::Publisher::Mongoid::Embedded
  extend ActiveSupport::Concern

  def payload
    super.merge(:id => instance.id)
  end

  module ClassMethods
    def publish(options)
      super

      options[:class].class_eval do
        callback = proc do
          if _parent.respond_to?(:promiscuous_publish_update)
            _parent.save
            _parent.reload # mongoid is not that smart, so we need to reload here.
            _parent.promiscuous_publish_update
          end
        end

        after_create callback
        after_update callback
        after_destroy callback
      end
    end
  end
end
