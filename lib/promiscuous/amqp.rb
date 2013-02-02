module Promiscuous::AMQP
  extend Promiscuous::Autoload
  autoload :Bunny, :RubyAMQP, :Null

  EXCHANGE = 'promiscuous'.freeze

  class << self
    attr_accessor :backend

    def backend=(value)
      @backend = "Promiscuous::AMQP::#{value.to_s.camelize.gsub(/amqp/, 'AMQP')}".constantize unless value.nil?
    end

    delegate :connect, :disconnect, :connected?, :publish, :open_queue, :to => :backend
  end
end
