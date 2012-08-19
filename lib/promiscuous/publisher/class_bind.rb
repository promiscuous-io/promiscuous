module Promiscuous::Publisher::ClassBind
  extend ActiveSupport::Concern

  module ClassMethods
    def publish(options)
      super

      unless options[:inherited] and options[:class]
        publisher_class = self
        klass.class_eval do
          class_attribute :promiscuous_publisher
          self.promiscuous_publisher = publisher_class
        end
      end
    end

    def klass
      if options[:class]
        options[:class].to_s.constantize
      else
        class_name = "::#{name.split('::').last}"
        class_name = $1 if class_name =~ /^(.+)Publisher$/
        class_name.constantize
      end
    end
  end
end
