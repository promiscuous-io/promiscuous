class Promiscuous::Error::Publisher < RuntimeError
  attr_accessor :inner, :instance, :out_of_sync

  def initialize(inner, options={})
    super(nil)
    inner = inner.inner if inner.is_a?(Promiscuous::Error::Publisher)
    set_backtrace(inner.backtrace)
    self.inner = inner
    self.instance = options[:instance]
    self.out_of_sync = options[:out_of_sync]
  end

  def message
    msg = "#{inner.class}: #{inner.message}"
    if instance
      msg = "#{msg} while publishing #{instance.inspect}"
      msg = "FATAL (out of sync) #{msg}" if out_of_sync
    end
    msg
  end

  def to_s
    message
  end
end
