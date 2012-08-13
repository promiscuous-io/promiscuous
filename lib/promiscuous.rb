require 'active_support/core_ext'
require 'promiscuous/config'
require 'promiscuous/amqp'
require 'promiscuous/loader'
require 'promiscuous/railtie' if defined?(Rails)

begin
  require 'mongoid'
  require 'active_record'
rescue LoadError
end

require 'promiscuous/publisher'
require 'promiscuous/subscriber'

module Promiscuous
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
