class Promiscuous::Publisher::Worker
  def initialize
    @recovery_timer = Promiscuous::Timer.new("recovery", Promiscuous::Config.recovery_timeout) { try_recover }
  end

  def start
    @recovery_timer.start(:run_immediately => true)
  end

  def stop
    @recovery_timer.reset
  end

  def try_recover
    Promiscuous::Publisher::Operation::Base.recover_locks
    Promiscuous::Publisher::Operation::Base.recover_payloads_for_rabbitmq
  rescue Exception => e
    Promiscuous.warn "[recovery] #{e}\n#{e.backtrace.join("\n")}"
    Promiscuous::Config.error_notifier.call(e)
  end
end
