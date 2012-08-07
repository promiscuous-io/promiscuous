module Replicable::Publisher::ClassBind
  extend ActiveSupport::Concern

  module ClassMethods
    def publish(options)
      super

      publisher_class = self
      options[:class].class_eval do
        class_attribute :replicable_publisher
        self.replicable_publisher = publisher_class
      end
    end
  end
end
