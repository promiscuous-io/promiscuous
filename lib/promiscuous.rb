require 'active_support/core_ext'

module Promiscuous
  require 'promiscuous/autoload'
  require 'promiscuous/railtie' if defined?(Rails)

  extend Promiscuous::Autoload
  autoload :Common, :Publisher, :Subscriber, :Observer, :Worker, :Ephemeral,
           :CLI, :Error, :Loader, :AMQP, :Config

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
