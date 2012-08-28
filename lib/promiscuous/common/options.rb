module Promiscuous::Common::Options
  extend ActiveSupport::Concern

  included do
    class_attribute :raw_options, :options, :options_mappings,
                    :instance_reader => false,
                    :instance_writer => false
    self.raw_options = {}
    self.options = {}
    self.options_mappings = {}
  end

  module ClassMethods
    def inherited(subclass)
      super
      subclass.options = self.options.dup
    end

    def use_option(attr, options={})
      instance_reader = options.fetch(:instance_reader, true)
      attr_alias = options.fetch(:as, attr)

      self.options_mappings[attr] = attr_alias

      base = self.ancestors[self.ancestors.index(Promiscuous::Common::Options) - 1]

      # We need to let all the modules overload these methods, which is
      # why we are injecting at the base level.
      base.singleton_class.class_eval do
        define_method("#{attr_alias}")  { self.options[attr] }
        define_method("#{attr_alias}=") { |value| self.options[attr] = value }
      end

      if instance_reader
        define_method("#{attr_alias}") { self.class.__send__("#{attr_alias}") }
      end

      self.__send__("#{attr_alias}=", raw_options[attr]) if raw_options[attr]
    end

    def load_options(options)
      self.raw_options = self.raw_options.dup
      self.raw_options.merge!(options)

      options.each do |attr, value|
        attr_alias = self.options_mappings[attr]
        self.__send__("#{attr_alias}=", value) if attr_alias
      end
    end
  end
end
