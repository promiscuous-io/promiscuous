class Promiscuous::Publisher::Mongoid::EmbeddedMany < Promiscuous::Publisher::Base
  module Payload
    def payload
      instance.map { |e| e.class.promiscuous_publisher.new(:instance => e).payload }
    end
  end
  include Payload

  include Promiscuous::Publisher::AMQP

  publish :to => '__promiscuous__/embedded_many'
end
