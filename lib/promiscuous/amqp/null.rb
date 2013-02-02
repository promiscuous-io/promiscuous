module Promiscuous::AMQP::Null
  def self.connect
  end

  def self.disconnect
  end

  def self.connected?
    true
  end

  def self.publish(options={})
  end

  def self.open_queue(options={}, &block)
  end
end
