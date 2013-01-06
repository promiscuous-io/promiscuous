module Promiscuous::Common::Worker
  extend ActiveSupport::Concern

  def initialize(options={})
    self.options = options
    self.stopped = true
    made_progress
  end

  def stop
    self.stopped = true
  end

  def resume
    self.stopped = false
  end

  def unit_of_work(type)
    # type is used by the new relic agent, by monkey patching.
    # middleware?
    if defined?(Mongoid)
      Mongoid.unit_of_work { yield }
    else
      yield
    end
  end

  def bareback?
    !!options[:bareback]
  end

  def stop_for_a_while(reason)
    stop
    self.retry_timeout = self.retry_timeout * 2

    if reason.inner.is_a? Promiscuous::Error::Connection
      "will retry when the amqp connection comes back"
    else
      EM::Timer.new(self.retry_timeout) { resume }
      "retrying in #{self.retry_timeout}s"
    end
  end

  def made_progress
    self.retry_timeout = 1
  end

  included do
    attr_accessor :stopped, :options, :retry_timeout
    alias_method :stopped?, :stopped
  end
end
