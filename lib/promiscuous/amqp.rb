module Promiscuous::AMQP
  extend Promiscuous::Autoload
  autoload :Bunny, :RubyAMQP, :Null

  EXCHANGE = 'promiscuous'.freeze

  class << self
    attr_accessor :backend

    def backend=(value)
      disconnect if @backend
      @backend = value.nil? ? nil : "Promiscuous::AMQP::#{value.to_s.camelize.gsub(/amqp/, 'AMQP')}".constantize
      connect if @backend
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
      backend.publish(options)
    end

    delegate :connect, :disconnect, :connected?, :to => :backend

    def const_missing(sym)
      backend.const_get(sym)
    end
  end
end
