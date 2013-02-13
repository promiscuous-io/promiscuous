require 'active_support/core_ext'

module Promiscuous
  require 'promiscuous/autoload'
  require 'promiscuous/railtie' if defined?(Rails)

  extend Promiscuous::Autoload
  autoload :Common, :Publisher, :Subscriber, :Observer, :Worker, :Ephemeral,
           :CLI, :Error, :Loader, :AMQP, :Redis, :Config, :DSL

  extend Promiscuous::DSL

  class << self
    def configure(&block)
      Config.configure(&block)
    end

    [:debug, :info, :error, :warn, :fatal].each do |level|
      define_method(level) do |msg|
        Promiscuous::Config.logger.__send__(level, "[promiscuous] #{msg}")
      end
    end

    def reload
      desc  = Promiscuous::Publisher::Base.descendants
      desc += Promiscuous::Subscriber::Base.descendants
      desc.reject! { |klass| klass.name =~ /^Promiscuous::/ }
      desc.each { |klass| klass.setup_class_binding }
    end

    def connect
      AMQP.connect
      Redis.connect
    end

    def disconnect
      AMQP.disconnect
      Redis.disconnect
    end

    def healthy?
      AMQP.ensure_connected
      Redis.ensure_connected
    rescue
      false
    else
      true
    end
  end

  module ConsoleHelpers
    # These are just for the subscriber, some helpers to debug in production
    def global_key
      Promiscuous::Redis.sub_key('global')
    end

    def global_version
      Promiscuous::Redis.get(global_key).to_i
    end

    def global_version=(value)
      Promiscuous::Redis.set(global_key, value)
      Promiscuous::Redis.publish(global_key, value)
      value
    end

    def global_version!
      version = Promiscuous::Redis.incr(global_key)
      Promiscuous::Redis.publish(global_key, version)
      version
    end
  end
  extend ConsoleHelpers

  at_exit { self.disconnect rescue nil }
end
