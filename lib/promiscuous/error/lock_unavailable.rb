class Promiscuous::Error::LockUnavailable < Promiscuous::Error::Base
  def initialize(lock)
    @lock = lock
  end

  def message
    "The lock is not available on #{@lock}\n" +
    "If an app instance died, the lock will expire in less than a minute."
  end

  alias to_s message
end
