module Promiscuous::AMQP
  autoload :Bunny,    'promiscuous/amqp/bunny'
  autoload :RubyAMQP, 'promiscuous/amqp/rubyamqp'
  autoload :Null,     'promiscuous/amqp/null'

  class << self
    def backend
      Promiscuous::Config.backend
    end

    delegate :connect, :disconnect, :publish, :subscribe, :to => :backend
  end
end
