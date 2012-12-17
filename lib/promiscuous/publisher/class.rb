module Promiscuous::Publisher::Class
  extend ActiveSupport::Concern
  include Promiscuous::Common::ClassHelpers

  included { use_option :class, :as => :klass }

  module ClassMethods
    def setup_class_binding
      publisher_class = self
      klass.class_eval do
        class_attribute :promiscuous_publisher
        self.promiscuous_publisher = publisher_class
      end if klass
    end

    def self.publish(options)
      super
      setup_class_binding
    end

    def inherited(subclass)
      super
      subclass.setup_class_binding unless options[:class]
    end

    def klass=(value)
      super
      setup_class_binding
    end

    def klass
      return nil if name.nil?
      "::#{super ? super : guess_class_name('Publishers')}".constantize
    end
  end
end
