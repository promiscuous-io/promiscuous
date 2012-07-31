require 'active_support/core_ext'
require 'replicable/amqp/bunny'
require 'replicable/amqp/fake'
require 'replicable/amqp/ruby-amqp'

module Replicable
  module AMQP
    mattr_accessor :backend
    mattr_accessor :app
    mattr_accessor :logger

    def self.configure(options={}, &block)
      backend = options[:backend]

      self.backend = "Replicable::AMQP::#{backend.to_s.camelize.gsub(/amqp/, 'AMQP')}".constantize
      self.backend.configure(options, &block)
      self.app = options[:app]
      self.logger = options[:logger] || Logger.new(STDOUT)
      self.logger.level = options[:logger_level] || Logger::WARN
      configure_logger
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
