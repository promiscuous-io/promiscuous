class Promiscuous::Error::Publisher < RuntimeError
  attr_accessor :inner, :instance, :out_of_sync

  def initialize(inner, options={})
    super(inner)
    set_backtrace(inner.backtrace)
    self.inner = inner
    self.instance = options[:instance]
    self.out_of_sync = options[:out_of_sync]
  end

  def message
    msg = "#{inner.class}: #{inner.message} while publishing #{instance.inspect}"
    msg = "FATAL (out of synch) #{msg}" if out_of_sync
    msg
  end

  def to_s
    message
  end
end
