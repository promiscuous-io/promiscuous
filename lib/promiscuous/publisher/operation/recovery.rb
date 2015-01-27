class Promiscuous::Publisher::Operation::Recovery < Promiscuous::Publisher::Operation::Base
  def initialize(options)
    super
    @locks = [options[:lock]]
  end

  def recover!
    @locks.each do |lock|
      if lock.try_extend
        recover_for_lock(lock)
        publish_payloads
      else
        # It's ok if the lock has been stolen. Another process is recovering.
        Promiscuous.warn "[recovery] Lock #{lock} was stolen during the recovery process"
      end
    end
  end
end

