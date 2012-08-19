require 'promiscuous/subscriber/envelope'

module Promiscuous::Subscriber::CustomClass
  extend ActiveSupport::Concern

  def klass
    self.class.klass
  end

  def instance
    @instance ||= fetch
  end

  included { use_option :class, :as => :klass }

  module ClassMethods
    def klass
      if super
        "::#{super}".constantize
      else
        class_name = "::#{name.split('::').last}"
        class_name = $1 if class_name =~ /^(.+)Subscriber$/
        class_name.constantize
      end
    end
  end
end
