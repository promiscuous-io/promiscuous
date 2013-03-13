class Promiscuous::Error::LostLock < Promiscuous::Error::Base
  def initialize(lock)
    @lock = lock
  end

  def message
    "The following lock was lost during the operation and will be recovered if not already done:\n" +
    "  #{@lock}"
  end

  alias to_s message
end
