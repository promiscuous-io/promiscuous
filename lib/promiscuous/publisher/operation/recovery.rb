class Promiscuous::Publisher::Operation::Recovery < Promiscuous::Publisher::Operation::Base
  def initialize(options)
    super
    @locks = [options[:lock]]
  end

  def recover!
    @locks.each do |lock|
      case lock.try_lock
      when :recovered
        # It's possible that if the lock was not recovered and the unlock
        # attempt below fails that we have a lock with no data.
        if lock.recovery_data
          recover_for_lock(lock)
          publish_payloads_async
        else
          lock.try_unlock
        end
      when true
        # Someone else completed recovery process. We don't need this lock
        lock.try_unlock
      when false
        # It's ok if the lock is unavailable as this means another recovery
        # process stole the lock and is processing the recovery
      end
    end
  end
end

