require 'active_support/core_ext'
require 'promiscuous/config'
require 'promiscuous/amqp'
require 'promiscuous/loader'
require 'promiscuous/railtie' if defined?(Rails)

module Promiscuous
  autoload :Common,     'promiscuous/common'
  autoload :Publisher,  'promiscuous/publisher'
  autoload :Subscriber, 'promiscuous/subscriber'
  autoload :Observer,   'promiscuous/observer'
  autoload :Worker,     'promiscuous/worker'
  autoload :Ephemeral,  'promiscuous/ephemeral'

  class << self
    def configure(&block)
      Config.configure(&block)
    end

    [:info, :error, :warn, :fatal].each do |level|
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
  end
end
