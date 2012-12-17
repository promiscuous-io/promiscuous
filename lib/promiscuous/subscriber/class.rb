module Promiscuous::Subscriber::Class
  extend ActiveSupport::Concern
  include Promiscuous::Common::ClassHelpers

  def instance
    @instance ||= fetch
  end

  included { use_option :class, :as => :klass }

  module ClassMethods
    def setup_class_binding; end

    def self.subscribe(options)
      super
      setup_class_binding
    end

    def klass=(value)
      super
      setup_class_binding
    end

    def klass
      return nil if name.nil?
      "::#{super ? super : guess_class_name('Subscribers')}".constantize
    end
  end
end
