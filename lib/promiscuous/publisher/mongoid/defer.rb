module Promiscuous::Publisher::Mongoid::Defer
  extend ActiveSupport::Concern
  include Promiscuous::Publisher::Envelope

  mattr_accessor :klasses
  mattr_accessor :collections
  self.klasses = {}
  self.collections = {}

  def publish
    super unless should_defer?
  end

  def payload
    super.merge(:version => instance._psv)
  end

  def should_defer?
    if options.has_key?(:defer)
      options[:defer]
    else
      operation == :update
    end
  end

  def self.hook_mongoid
    return if @mongoid_hooked
    @mongoid_hooked = true

    Moped::Query.class_eval do
      alias_method :update_orig, :update
      def update(change, flags = nil)
        if Promiscuous::Publisher::Mongoid::Defer.collections[@collection.name]
          change = change.dup
          change['$set'] ||= {}
          change['$inc'] ||= {}
          change['$set'].merge!(:_psp => true)
          change['$inc'].merge!(:_psv => 1)
        end
        update_orig(change, flags)
      end
    end
  end

  module ClassMethods
    def setup_class_binding
      super
      klass.class_eval do
        cattr_accessor :publisher_defer_hooked
        return if self.publisher_defer_hooked
        self.publisher_defer_hooked = true

        # TODO Make sure we are not overriding a field, although VERY unlikly
        field :_psp, :type => Boolean
        field :_psv, :type => Integer
        index({:_psp => 1}, :background => true, :sparse => true)

        Promiscuous::Publisher::Mongoid::Defer.hook_mongoid
        Promiscuous::Publisher::Mongoid::Defer.klasses[self.to_s] = self
        Promiscuous::Publisher::Mongoid::Defer.collections[collection.name] = true
      end if klass
    end
  end
end
