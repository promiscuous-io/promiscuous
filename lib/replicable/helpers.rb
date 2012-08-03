module Replicable
  module Helpers
    extend ActiveSupport::Concern

    module ClassMethods
      def replicate(options={}, &block)
        class_attribute :replicate_options unless replicated_called?

        # The subclass needs to use the class attribute setter to get its own
        # copy.
        self.replicate_options = Marshal.load(Marshal.dump(self.replicate_options))

        proxy = Proxy.new(self)
        proxy.instance_eval(&block) if block_given?

        self.replicate_options ||= {}
        self.replicate_options.merge!(options)
        self.replicate_options[:fields] ||= []
        self.replicate_options[:fields] += proxy.fields
      end

      def replicated_called?
        defined?(replicate_options)
      end

      def replicate_ancestors
        model = self
        chain = []
        while model.include?(Mongoid::Document) do
          chain << model
          model = model.superclass
        end
        chain.reverse.map { |c| c.to_s.underscore }
      end
    end

    class Proxy
      attr_accessor :base, :fields
      def initialize(base)
        @base = base
        @fields = []
      end

      def field(field_name, *args)
        @base.field(field_name, *args)
        @fields << field_name
      end

      def belongs_to(associated_model, *args)
        @base.belongs_to(associated_model, *args)
        @fields << :"#{associated_model}_id"
      end
    end

  end
end
