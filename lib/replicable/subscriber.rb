require 'active_support/concern'
require 'set'

module Replicable::Subscriber
  extend ActiveSupport::Concern

  mattr_accessor :subscriptions
  self.subscriptions = Set.new

  module ClassMethods
    def replicate(options={}, &block)
      raise "Can't replicate on nested models" if defined?(replicate_fields)
      class_attribute :replicate_options
      Replicable::Subscriber.subscriptions << self
      proxy = Proxy.new(self)
      proxy.instance_eval(&block)
      options[:fields] = proxy.fields
      self.replicate_options = options
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
  end
end
