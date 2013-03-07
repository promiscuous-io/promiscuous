class Promiscuous::Error::Recovery < Promiscuous::Error::Base
  def initialize(message, inner=nil)
    message = "#{inner.class}: #{inner} -- #{message}" if inner
    super(message)
    set_backtrace(inner.backtrace) if inner
  end
end
