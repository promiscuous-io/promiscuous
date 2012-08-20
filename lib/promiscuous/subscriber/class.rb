module Promiscuous::Subscriber::Class
  extend ActiveSupport::Concern

  def instance
    @instance ||= fetch
  end

  included { use_option :class, :as => :klass }

  module ClassMethods
    def klass
      if super
        "::#{super}".constantize
      elsif name
        class_name = "::#{name.split('::').last}"
        class_name = $1 if class_name =~ /^(.+)Subscriber$/
        class_name.constantize
      end
    end
  end
end
