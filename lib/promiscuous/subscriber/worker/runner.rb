class Promiscuous::Subscriber::Worker::Runner
  attr_accessor :messages_to_process

  def initialize(root)
    @root = root
    @messages_to_process = Queue.new
  end

  def start
    num_threads = Promiscuous::Config.subscriber_threads
    @locks   ||= num_threads.times.map { Mutex.new }
    @threads ||= num_threads.times.map { |i| Thread.new { main_loop(@locks[i]) } }
  end

  def stop
    return unless @threads
    @threads.zip(@locks).each { |thread, lock| lock.synchronize { thread.kill } }
    @threads = @locks = nil
    @messages_to_process.clear
  end

  def main_loop(lock)
    loop do
      msg = @messages_to_process.pop
      lock.synchronize { msg.process }
    end
  end
end
