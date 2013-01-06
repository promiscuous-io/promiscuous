module Promiscuous::Publisher::AMQP
  extend ActiveSupport::Concern
  include Promiscuous::Publisher::Envelope

  def publish
    exchange_name = Promiscuous::AMQP::EXCHANGE
    exchange_name += ".#{options[:personality]}" if options[:personality]
    Promiscuous::AMQP.publish(:exchange_name => exchange_name, :key => to, :payload => payload.to_json)
  rescue Exception => e
    raise Promiscuous::Error::Publisher.new(e, :instance => instance, :out_of_sync => true)
  end

  def payload
    super.merge(:__amqp__ => to)
  end

  included { use_option :to }
end
