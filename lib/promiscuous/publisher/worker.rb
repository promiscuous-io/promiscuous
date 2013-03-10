class Promiscuous::Publisher::Worker < Celluloid::SupervisionGroup
  class Recover
    include Celluloid
    task_class TaskThread

    def initialize
      after(1.second) { try_recover }
    end

    def try_recover
      Promiscuous::Publisher::Operation::Base.recover_locks
      Promiscuous::Publisher::Operation::Base.recover_payloads_for_rabbitmq
    rescue Exception => e
      Promiscuous.warn "[recovery] #{e} #{e.backtrace.join("\n")}"
      Promiscuous::Config.error_notifier.try(:call, e)
    ensure
      after(Promiscuous::Config.recovery_timeout) { try_recover }
    end
  end

  supervise Recover, :as => :publisher_recover_worker
end
