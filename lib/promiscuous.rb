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

  class << self
    def configure(&block)
      Config.configure(&block)
    end

    [:info, :error, :warn, :fatal].each do |level|
      define_method(level) do |msg|
        Promiscuous::Config.logger.__send__(level, "[promiscuous] #{msg}")
      end
    end
  end
end
