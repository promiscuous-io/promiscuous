module Promiscuous::AMQP
  extend Promiscuous::Autoload
  autoload :HotBunny, :Bunny, :Null, :Fake

  PUB_EXCHANGE = ENV['PUB_EXCHANGE'] || 'promiscuous'
  SUB_EXCHANGE = ENV['SUB_EXCHANGE'] || 'promiscuous'

  class << self
    attr_accessor :backend
    attr_accessor :backend_class

    def backend=(value)
      disconnect
      @backend_class = value.nil? ? nil : "Promiscuous::AMQP::#{value.to_s.camelize.gsub(/amqp/, 'AMQP')}".constantize
      connect if @backend_class
    end

    def lost_connection_exception
      Promiscuous::Error::Connection.new(:service => :amqp)
    end

    def ensure_connected
      raise lost_connection_exception unless connected?
    end

    def publish(options={})
      ensure_connected
      Promiscuous.debug "[publish] #{options[:key]} -> #{options[:payload]}"
      backend.respond_to?(:async) ? backend.async.publish(options) : backend.publish(options)
    end

    def connect
      return if @backend
      @backend = backend_class.new
      @backend.connect
    end

    def disconnect
      return unless @backend
      @backend.disconnect
      @backend.terminate if @backend.respond_to?(:terminate)
      @backend = nil
    end

    delegate :connected?, :to => :backend

    def const_missing(sym)
      backend_class.const_get(sym)
    end
  end
end
