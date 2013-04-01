class Promiscuous::Subscriber::Worker
  extend Promiscuous::Autoload
  autoload :Message, :Pump, :MessageSynchronizer, :Runner, :Stats, :Recorder

  attr_accessor :message_synchronizer, :pump, :runner, :stats

  def initialize
    @message_synchronizer = MessageSynchronizer.new(self)
    @pump = Pump.new(self)
    @runner = Runner.new(self)
    @stats = Stats.new
  end

  def start
    @message_synchronizer.connect
    @pump.connect
    @runner.start
    @stats.connect
  end

  def stop
    @stats.disconnect
    @pump.disconnect
    @message_synchronizer.disconnect
    @runner.stop
  end
end
