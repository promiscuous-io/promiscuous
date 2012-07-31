Replicable::AMQP.instance_eval do
  mattr_accessor :messages
  self.messages = []

  def self.publish(msg)
    self.messages << msg
  end

  def self.clear
    self.messages.clear
  end
end
