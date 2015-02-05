class Promiscuous::Subscriber::Worker
  extend Promiscuous::Autoload
  autoload :Pump, :Distributor, :Runner, :Stats, :Recorder, :EventualDestroyer

  attr_accessor :pump, :runner, :stats, :eventual_destroyer

  def initialize
    # inject what we need for our backend
    extend Promiscuous::Backend.subscriber_worker_module

    @stats = Stats.new
    @eventual_destroyer = EventualDestroyer.new

    backend_subscriber_initialize(self)
  end

  def start
    @stats.connect
    @eventual_destroyer.try(:start)

    backend_subscriber_start
  end

  def stop
    @stats.disconnect
    @eventual_destroyer.try(:stop)

    backend_subscriber_stop
  end

  def show_stop_status
    @num_show_stop_requests ||= 0
    @num_show_stop_requests += 1

    backend_subscriber_show_stop_status(@num_show_stop_requests)
  end
end
