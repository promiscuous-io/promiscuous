require 'active_support/concern'
require 'set'

module Replicable::Subscriber
  extend ActiveSupport::Concern
  include Replicable::Helpers

  mattr_accessor :subscriptions
  self.subscriptions = Set.new

  module ClassMethods
    def replicate(options={}, &block)
      Replicable::Subscriber.subscriptions << self
      super
    end
  end
end
