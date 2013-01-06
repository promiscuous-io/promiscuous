module Promiscuous::AMQP
  extend Promiscuous::Autoload
  autoload :Bunny, :RubyAMQP, :Null

  EXCHANGE = 'promiscuous'.freeze

  class << self
    def backend
      Promiscuous::Config.backend
    end

    delegate :connect, :disconnect, :connected?, :publish, :open_queue, :to => :backend
  end
end
