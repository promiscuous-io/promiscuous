class Promiscuous::Error::Publisher < Promiscuous::Error::Base
  attr_accessor :inner, :instance, :payload

  def initialize(inner, options={})
    super(nil)
    inner = inner.inner if inner.is_a?(Promiscuous::Error::Publisher)
    set_backtrace(inner.backtrace)
    self.inner = inner
    self.instance = options[:instance]
    self.payload  = options[:payload]
  end

  def message
    msg = "#{inner.class}: #{inner.message}"
    msg = "#{msg} while publishing #{instance.inspect}" if instance
    msg = "#{msg} payload: #{payload}" if payload
    msg
  end

  alias to_s message
end
