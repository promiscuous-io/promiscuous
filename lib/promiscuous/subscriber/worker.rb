class Promiscuous::Subscriber::Worker
  require 'celluloid'
  require 'celluloid/io'

  extend Promiscuous::Autoload
  autoload :Message, :Pump, :MessageSynchronizer, :Runner

  attr_accessor :options, :stopped, :pump, :message_synchronizer, :runners
  alias_method :stopped?, :stopped

  def initialize(options={})
    Celluloid.exception_handler { |e| Promiscuous::Config.error_notifier.try(:call, e) }

    self.options = options
    self.stopped = true

    self.pump = Pump.new(self)
  end

  def start
    return unless self.stopped
    self.stopped = false
    self.runners = Runner.pool
    self.message_synchronizer = MessageSynchronizer.new(self)
    self.message_synchronizer.start
    self.pump.start
  end

  def stop
    return if self.stopped
    self.pump.stop
    self.message_synchronizer.stop rescue Celluloid::Task::TerminatedError
    self.message_synchronizer = nil
    self.runners.terminate
    self.runners = nil
    self.stopped = true
    # TODO wait for the runners to finish
  end

  def unit_of_work(type, &block)
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
