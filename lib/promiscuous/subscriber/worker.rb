class Promiscuous::Subscriber::Worker
  extend Promiscuous::Autoload
  autoload :Message, :Pump, :MessageSynchronizer, :Runner, :Stats, :Recorder,
           :EventualDestroyer

  attr_accessor :message_synchronizer, :pump, :runner, :stats, :eventual_destroyer

  def initialize
    @message_synchronizer = MessageSynchronizer.new(self)
    @pump = Pump.new(self)
    @runner = Runner.new(self)
    @stats = Stats.new
    @eventual_destroyer = EventualDestroyer.new if Promiscuous::Config.consistency == :eventual
  end

  def start
    @message_synchronizer.connect
    @pump.connect
    @runner.start
    @stats.connect
    @eventual_destroyer.try(:start)
  end

  def stop
    @stats.disconnect
    @runner.stop
    @pump.disconnect
    @message_synchronizer.disconnect
    @eventual_destroyer.try(:stop)
  end

  def show_stop_status
    @num_show_stop_requests ||= 0
    @num_show_stop_requests += 1
    @runner.show_stop_status(@num_show_stop_requests)
  end
end
