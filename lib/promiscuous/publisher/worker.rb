class Promiscuous::Publisher::Worker
  def initialize
    @transport_worker = Promiscuous::Publisher::Transport::Worker.new
  end

  def start
    @transport_worker.start
  end

  def stop
    @transport_worker.stop
  end
end
