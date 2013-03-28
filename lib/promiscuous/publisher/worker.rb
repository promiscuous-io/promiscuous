class Promiscuous::Publisher::Worker
  def start
    try_recover_later(0)
  end

  def stop
    @recovery_timer = nil
  end

  def try_recover_later(timeout=nil)
    timeout ||= Promiscuous::Config.recovery_timeout
    @recovery_timer ||= Thread.new { sleep timeout; try_recover }
  end

  def try_recover
    return unless @recovery_timer == Thread.current
    @recovery_timer = nil

    Promiscuous::Publisher::Operation::Base.recover_locks
    Promiscuous::Publisher::Operation::Base.recover_payloads_for_rabbitmq
  rescue Exception => e
    Promiscuous.warn "[recovery] #{e} #{e.backtrace.join("\n")}"
    Promiscuous::Config.error_notifier.try(:call, e)
  ensure
    try_recover_later
  end
end
