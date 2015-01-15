class Promiscuous::Publisher::Operation::Recovery < Promiscuous::Publisher::Operation::Base
  def initialize(options)
    super
    @lock = options[:lock]
  end

  def recover!
    if @lock.try_lock
      recover_for_lock(@lock)
    end

    publish_payloads_async
  end
end

