require 'active_support/core_ext'
require 'active_model/callbacks'
require 'multi_json'

module Promiscuous
  def self.require_for(gem, file)
    require gem
    require file
  rescue LoadError
  end

  require 'promiscuous/autoload'
  require_for 'rails',   'promiscuous/railtie'
  require_for 'resque',  'promiscuous/resque'
  require_for 'sidekiq', 'promiscuous/sidekiq'
  require_for 'mongoid', 'promiscuous/mongoid'

  extend Promiscuous::Autoload
  autoload :Common, :Publisher, :Subscriber, :Observer, :Worker, :Ephemeral,
           :CLI, :Error, :Loader, :AMQP, :Redis, :ZK, :Config, :DSL, :Key,
           :Convenience, :Dependency, :Timer, :Instrumentation

  # Shortcut for the middleware, TODO make load on demand
  Middleware = Publisher::Context::Middleware

  extend Promiscuous::DSL

  Object.__send__(:include, Promiscuous::Convenience)

  class << self
    def configure(&block)
      Config.configure(&block)
    end

    [:debug, :info, :error, :warn, :fatal].each do |level|
      define_method(level) do |msg|
        Promiscuous::Config.logger.__send__(level, "[promiscuous] #{msg}")
      end
    end

    def connect
      AMQP.connect
      Redis.connect
      @should_be_connected = true
    end

    def disconnect
      AMQP.disconnect
      Redis.disconnect
      @should_be_connected = false
    end

    def should_be_connected?
      !!@should_be_connected
    end

    def healthy?
      AMQP.ensure_connected
      Redis.ensure_connected
    rescue Exception
      false
    else
      true
    end

    def ensure_connected
      unless should_be_connected?
        connect
      end
    end

    def disabled
      return $promiscuous_disabled if Thread.current[:promiscuous_disabled].nil?
      Thread.current[:promiscuous_disabled]
    end

    def disabled=(value)
      Thread.current[:promiscuous_disabled] = value
    end

    def disabled?
      !!Thread.current[:promiscuous_disabled]
    end

    def context(*args, &block)
      Publisher::Context::Base.with_context(*args, &block)
    end
  end

  at_exit { self.disconnect rescue nil }
end
