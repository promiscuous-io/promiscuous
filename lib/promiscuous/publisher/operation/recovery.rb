class Promiscuous::Publisher::Operation::Recovery < Promiscuous::Publisher::Operation::Base
  def initialize(options)
    super
    @lock = options[:lock]
  end

  def recover!
    begin
      @lock.recover
      recover_for_lock(@lock)
    rescue Redis::Lock::Timeout, Redis::Lock::LostLock
      # Another process recovered
    end

    publish_payloads_async
  end
end

