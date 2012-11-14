module Promiscuous::AMQP
  autoload :Bunny,    'promiscuous/amqp/bunny'
  autoload :RubyAMQP, 'promiscuous/amqp/rubyamqp'
  autoload :Null,     'promiscuous/amqp/null'

  EXCHANGE = 'promiscuous'.freeze

  class << self
    def backend
      Promiscuous::Config.backend
    end

    delegate :connect, :disconnect, :publish, :open_queue, :to => :backend
  end
end
