module Promiscuous::AMQP
  extend Promiscuous::Autoload
  autoload :Bunny, :RubyAMQP, :Null

  EXCHANGE = 'promiscuous'.freeze

  class << self
    attr_accessor :backend

    def backend=(value)
      @backend = "Promiscuous::AMQP::#{value.to_s.camelize.gsub(/amqp/, 'AMQP')}".constantize unless value.nil?
    end

    def lost_connection_exception
      Promiscuous::Error::Connection.new(:service => :amqp)
    end

    def ensure_connected
      raise lost_connection_exception unless connected?
    end

    def publish(options={})
      ensure_connected
      Promiscuous.debug "[publish] (#{options[:exchange_name]}) #{options[:key]} -> #{options[:payload]}"
      backend.publish(options)
    end

    delegate :connect, :disconnect, :connected?, :open_queue, :to => :backend
  end
end
