class Promiscuous::Subscriber::MessageProcessor::Base
  attr_accessor :message

  def initialize(message)
    self.message = message
  end

  def operations
    message.parsed_payload['operations'].map { |op| operation_class.new(op) }
  end

  def self.process(*args)
    raise "Same thread is processing a message?" if self.current

    begin
      self.current = new(*args)
      self.current.on_message
    ensure
      self.current = nil
    end
  end

  def self.current
    Thread.current[:promiscuous_message_processor]
  end

  def self.current=(value)
    Thread.current[:promiscuous_message_processor] = value
  end

  def on_message
    raise "Must be implemented"
  end

  def operation_class
    raise "Must be implemented"
  end
end
