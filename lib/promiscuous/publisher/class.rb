module Promiscuous::Publisher::Class
  extend ActiveSupport::Concern
  include Promiscuous::Common::ClassHelpers

  included { use_option :class, :as => :klass }

  module ClassMethods
    def setup_binding
      publisher_class = self
      klass.class_eval do
        class_attribute :promiscuous_publisher
        self.promiscuous_publisher = publisher_class
      end if klass
    end

    def inherited(subclass)
      super
      subclass.setup_binding unless options[:class]
    end

    def klass=(value)
      super
      setup_binding
    end

    def klass
      if super
        "::#{super}".constantize
      elsif name
        guess_class_name('Publishers').constantize
      end
    end
  end
end
