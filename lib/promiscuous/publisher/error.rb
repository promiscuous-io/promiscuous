class Promiscuous::Publisher::Error < RuntimeError
  attr_accessor :inner, :instance

  def initialize(inner, instance)
    super(inner)
    set_backtrace(inner.backtrace)
    self.inner = inner
    self.instance = instance
  end

  def message
    "#{inner.message} while processing #{instance}"
  end

  def to_s
    message
  end
end
