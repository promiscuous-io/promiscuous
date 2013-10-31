class Promiscuous::Subscriber::Worker::Runner
  attr_accessor :messages_to_process

  def initialize(root)
    @root = root
    @messages_to_process = Queue.new
  end

  def start
    num_threads = Promiscuous::Config.subscriber_threads
    @runner_threads ||= num_threads.times.map { RunnerThread.new(@messages_to_process) }
  end

  def stop
    return unless @runner_threads

    @runner_threads.each { |runner_thread| runner_thread.stop }
    @runner_threads = nil

    @messages_to_process.clear
  end

  def show_stop_status(num_requests)
    @runner_threads.each { |runner_thread| runner_thread.show_stop_status(num_requests) }
  end

  class RunnerThread
    def initialize(message_queue)
      @message_queue = message_queue
      @kill_lock = Mutex.new
      @thread = Thread.new { main_loop }
    end

    def main_loop
      loop do
        msg = @message_queue.pop
        @kill_lock.synchronize do
          @current_message = msg
          msg.process # msg.process does not throw
          @current_message = nil
        end
      end
    end

    def stop
      @kill_lock.synchronize { @thread.kill }
    end

    def show_stop_status(num_requests)
      msg = @current_message
      backtrace = @thread.backtrace

      if msg
        STDERR.puts "Still processing #{msg.payload}"

        if num_requests > 1 && backtrace
          STDERR.puts
          STDERR.puts backtrace.map { |line| "  \e[1;30m#{line}\e[0m\n" }
          STDERR.puts
          STDERR.puts "I'm a little busy, check out my stack trace."
          STDERR.puts "Be patient (or kill me with -9, but that wouldn't be very nice of you)."
        else
          STDERR.puts "Just a second..."
        end
      end
    end
  end
end
