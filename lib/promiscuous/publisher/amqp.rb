module Promiscuous::Publisher::AMQP
  extend ActiveSupport::Concern
  include Promiscuous::Publisher::Envelope

  def amqp_publish
    Promiscuous::AMQP.publish(:key => to, :payload => payload.to_json)
  end

  def payload
    super.merge(:__amqp__ => to)
  end

  included { use_option :to }
end
