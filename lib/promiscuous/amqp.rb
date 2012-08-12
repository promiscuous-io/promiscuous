require 'promiscuous/amqp/bunny'
require 'promiscuous/amqp/rubyamqp'
require 'promiscuous/amqp/null'

module Promiscuous
  module AMQP
    class << self
      def backend
        Promiscuous::Config.backend
      end

      delegate :connect, :disconnect, :publish, :subscribe, :to => :backend
    end
  end
end
