# This is a temporary class while we roll out moving to Kafka
# It does a few things differently:
# - Publishing will go across both AMQP & Kafka
# - Subscribing will be from Rabbit only, use :poseidon as a backend for Kafka
#
class Promiscuous::Backend::Both < Promiscuous::Backend::Bunny
  def initialize
    @kafka = nil
    super
  end

  def connect
    @kafka = Promiscuous::Backend::Poseidon.new
    @kafka.connect
    super
  end

  def disconnect
    @kafka.disconnect
    super
  end

  def connected?
    super && @kafka.connected?
  end

  def publish(options={})
    @kafka.publish(options)
    super(options)
  end
end
