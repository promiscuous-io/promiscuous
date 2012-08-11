class Promiscuous::Subscriber::Error < RuntimeError
  attr_accessor :inner, :payload

  def initialize(inner, payload)
    super(inner)
    set_backtrace(inner.backtrace)
    self.inner = inner
    self.payload = payload
  end

  def message
    "#{inner.message} while processing #{payload}"
  end

  def to_s
    message
  end
end
