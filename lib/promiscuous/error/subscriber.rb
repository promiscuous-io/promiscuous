class Promiscuous::Error::Subscriber < RuntimeError
  attr_accessor :inner, :payload

  def initialize(inner, options={})
    super(nil)
    set_backtrace(inner.backtrace)
    self.inner = inner
    self.payload = options[:payload]
  end

  def message
    "#{inner.class}: #{inner.message} while processing #{payload}"
  end

  def to_s
    message
  end
end
