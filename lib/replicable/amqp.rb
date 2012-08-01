require 'active_support/core_ext'
require 'replicable/amqp/bunny'
require 'replicable/amqp/fake'
require 'replicable/amqp/ruby-amqp'

module Replicable
  module AMQP
    mattr_accessor :backend, :app, :logger, :error_handler

    def self.configure(options={}, &block)
      backend = options[:backend]

      self.backend = "Replicable::AMQP::#{backend.to_s.camelize.gsub(/amqp/, 'AMQP')}".constantize
      self.backend.configure(options, &block)
      self.app           = options[:app]
      self.logger        = options[:logger] || Logger.new(STDOUT).tap { |l| l.level = Logger::WARN }
      self.error_handler = options[:error_handler]
      configure_logger
      self
    end

    def self.configure_logger
      self.logger.formatter = proc do |severity, datetime, progname, msg|
        "[AMQP] #{msg}\n"
      end
    end

    # TODO Evaluate the performance hit of method_missing
    def self.method_missing(method, *args, &block)
      self.backend.__send__(method, *args, &block)
    end
  end
end
