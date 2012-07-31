require 'active_support/core_ext'
require 'replicable/amqp/bunny'
require 'replicable/amqp/fake'
require 'replicable/amqp/ruby-amqp'

module Replicable
  module AMQP
    mattr_accessor :backend
    mattr_accessor :app

    def self.configure(options={}, &block)
      backend = options[:backend]
      app = options[:app]

      self.backend = "Replicable::AMQP::#{backend.to_s.camelize.gsub(/amqp/, 'AMQP')}".constantize
      self.backend.configure(options, &block)
      self.app = app
    end

    # TODO Evaluate the performance hit of method_missing
    def self.method_missing(method, *args, &block)
      self.backend.__send__(method, *args, &block)
    end
  end
end
