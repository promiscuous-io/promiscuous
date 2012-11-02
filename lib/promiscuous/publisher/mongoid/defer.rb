module Promiscuous::Publisher::Mongoid::Defer
  extend ActiveSupport::Concern

  mattr_accessor :klasses
  mattr_accessor :collections
  self.klasses = {}
  self.collections = {}

  def publish
    super unless should_defer?
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
          psp_field = :_psp
          change = change.dup
          change['$set'] ||= {}
          change['$set'].merge!(psp_field => true)
        end
        update_orig(change, flags)
      end
    end
  end

  included do
    klass.class_eval do
      cattr_accessor :publisher_defer_hooked
      return if self.publisher_defer_hooked
      self.publisher_defer_hooked = true

      # TODO Make sure we are not overriding a field, although VERY unlikly
      field :_psp, :type => Boolean
      index({:_psp => 1}, :background => true, :sparse => true)

      Promiscuous::Publisher::Mongoid::Defer.hook_mongoid
      Promiscuous::Publisher::Mongoid::Defer.klasses[self.to_s] = self
      Promiscuous::Publisher::Mongoid::Defer.collections[collection.name] = true
    end
  end
end
