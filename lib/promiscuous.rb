require 'active_support/dependencies/autoload'
require 'active_support/deprecation'
require 'active_support/core_ext'
require 'active_model/callbacks'

require 'multi_json'

module Promiscuous
  def self.require_for(gem, file)
    only_for(gem) { require file }
  end

  def self.only_for(gem, &block)
    require gem
    block.call
  rescue LoadError
  end

  require 'promiscuous/autoload'
  require_for 'rails',   'promiscuous/railtie'
  require_for 'resque',  'promiscuous/resque'
  require_for 'sidekiq', 'promiscuous/sidekiq'
  require_for 'mongoid', 'promiscuous/mongoid'

  extend Promiscuous::Autoload
  autoload :Common, :Publisher, :Subscriber, :Observer, :Worker, :Ephemeral,
           :CLI, :Error, :Loader, :Backend, :Redis, :ZK, :Config, :DSL, :Key,
           :Convenience, :Dependency, :Timer, :Rabbit

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
      Backend.connect
      Redis.connect

      @should_be_connected = true
    end

    def disconnect
      Backend.disconnect
      Redis.disconnect
      @should_be_connected = false
    end

    def should_be_connected?
      !!@should_be_connected
    end

    def health_check
      health = { :backend  => true, :redis => true }

      begin
        Backend.ensure_connected
      rescue StandardError
        health[:backend] = false
      end

      begin
        Redis.ensure_connected
      rescue StandardError
        health[:redis] = false
      end

      health[:status]  = health.all?{|key, value| value == true} ?  :ok : :service_unavailable
      health[:expired] = Promiscuous::Publisher::Operation::Base.expired.length

      health
    end

    def healthy?
      health_check[:status] == :ok
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

    def context
      Publisher::Context::Base.current
    end
  end

  at_exit { self.disconnect rescue nil }
end
