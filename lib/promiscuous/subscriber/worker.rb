class Promiscuous::Subscriber::Worker
  extend Promiscuous::Autoload
  autoload :Message, :Pump, :MessageSynchronizer

  attr_accessor :options, :stopped, :pump, :message_synchronizer
  alias_method :stopped?, :stopped

  def initialize(options={})
    self.options = options
    self.stopped = true

    @lock = Mutex.new

    self.message_synchronizer = MessageSynchronizer.new(self)
    self.pump = Pump.new(self)
  end

  def resume
    @lock.synchronize do
      return unless self.stopped
      self.stopped = false
      self.message_synchronizer.resume
      self.pump.resume
    end
  end

  def stop
    @lock.synchronize do
      return if self.stopped
      self.pump.stop
      self.message_synchronizer.stop
      self.stopped = true
    end
  end

  def stop_for_a_while(reason)
    stop
    #self.retry_timeout = self.retry_timeout * 2

    #if reason.inner.is_a? Promiscuous::Error::Connection
      #"will retry when the #{reason.which} connection comes back"
    #else
      #EM::Timer.new(self.retry_timeout) { resume }
      #"retrying in #{self.retry_timeout}s"
    #end
  end


  def unit_of_work(type)
    # type is used by the new relic agent, by monkey patching.
    # middleware?
    if defined?(Mongoid)
      Mongoid.unit_of_work { yield }
    else
      yield
    end
  ensure
    if defined?(ActiveRecord)
      ActiveRecord::Base.clear_active_connections!
    end
  end
end
