class Promiscuous::Subscriber::Worker
  extend Promiscuous::Autoload
  autoload :Pump, :Distributor, :Runner, :Stats, :Recorder, :EventualDestroyer

  attr_accessor :pump, :runner, :stats, :eventual_destroyer

  def initialize
    @pump = Pump.new(self)
    @distributor = Distributor.new(self)
    @runner = Runner.new(self)
    @stats = Stats.new
    @eventual_destroyer = EventualDestroyer.new
  end

  def start
    @pump.connect
    @distributor.start
    @runner.start
    @stats.connect
    @eventual_destroyer.try(:start)
  end

  def stop
    @stats.disconnect
    @runner.stop
    @pump.disconnect
    @distributor.stop
    @eventual_destroyer.try(:stop)
  end

  def show_stop_status
    @num_show_stop_requests ||= 0
    @num_show_stop_requests += 1
    @runner.show_stop_status(@num_show_stop_requests)
  end
end
