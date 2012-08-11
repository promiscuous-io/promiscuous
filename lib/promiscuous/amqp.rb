require 'promiscuous/amqp/bunny'
require 'promiscuous/amqp/fake'
require 'promiscuous/amqp/ruby-amqp'
require 'promiscuous/amqp/null'

module Promiscuous
  module AMQP
    mattr_accessor :backend, :app, :logger, :error_handler

    def self.configure(options={}, &block)
      options.symbolize_keys!

      self.backend = "Promiscuous::AMQP::#{options[:backend].to_s.camelize.gsub(/amqp/, 'AMQP')}".constantize
      self.backend.configure(options, &block)
      self.app           = options[:app]
      self.logger        = options[:logger] || Logger.new(STDOUT).tap { |l| l.level = Logger::WARN }
      self.error_handler = options[:error_handler]
      self
    end

    class << self
      [:info, :error, :warn, :fatal].each do |level|
        define_method(level) do |msg|
          self.logger.__send__(level, "[AMQP] #{msg}")
        end
      end
    end

    # TODO Evaluate the performance hit of method_missing
    def self.method_missing(method, *args, &block)
      self.backend.__send__(method, *args, &block)
    end
  end
end
