class Promiscuous::Subscriber::Worker::Runner
  attr_accessor :messages_to_process

  def initialize(root)
    @root = root
    @messages_to_process = Queue.new
  end

  def start
    @threads ||= Promiscuous::Config.subscriber_threads.times.map { Thread.new { main_loop } }
  end

  def stop
    @threads.each(&:kill) # TODO Graceful stop
    @threads = nil
  end

  def main_loop
    loop do
      msg = @messages_to_process.pop
      msg.process
    end
  end
end
