class Promiscuous::Publisher::Worker < Celluloid::SupervisionGroup
  class Recover
    include Celluloid

    def initialize
      after(1.second) { try_recover }
    end

    def try_recover
      Promiscuous::Publisher::Operation::Base.recover_locks
      Promiscuous::Publisher::Operation::Base.recover_payloads_for_rabbitmq
      after(Promiscuous::Config.recovery_timeout)
    end
  end

  supervise Recover, :as => :publisher_recover_worker
end
