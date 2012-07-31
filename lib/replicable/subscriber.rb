require 'active_support/concern'
require 'set'

module Replicable::Subscriber
  extend ActiveSupport::Concern

  mattr_accessor :subscriptions
  self.subscriptions = Set.new

  module ClassMethods
    def replicate(options={})
      raise "Can't replicate on nested models" if defined?(replicate_fields)
      class_attribute :replicate_options
      self.replicate_options = options
      Replicable::Subscriber.subscriptions << self
    end
  end
end
