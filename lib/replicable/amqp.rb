require 'active_support/core_ext'
require 'replicable/amqp/bunny'
require 'replicable/amqp/fake'
require 'replicable/amqp/ruby-amqp'

module Replicable
  module AMQP
    mattr_accessor :backend

    def self.configure(backend, *args, &block)
      self.backend = "Replicable::AMQP::#{backend.to_s.camelize}".constantize
      self.backend.configure(*args, &block)
    end

    # TODO Evaluate the performance hit of method_missing
    def self.method_missing(method, *args, &block)
      self.backend.__send__(method, *args, &block)
    end
  end
end
