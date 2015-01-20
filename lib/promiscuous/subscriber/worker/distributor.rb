class Promiscuous::Subscriber::Worker::Distributor
  def initialize(root)
    @root = root
  end

  def start
    num_threads = Promiscuous::Config.subscriber_threads
    Promiscuous.debug "[kafka] Booting #{num_threads} threads per topic"
    Promiscuous::Config.subscriber_topics.each do |topic|
      @distributor_threads ||= num_threads.times.map { DistributorThread.new(topic) }
    end
  end

  def stop
    return unless @distributor_threads

    @distributor_threads.each { |distributor_thread| distributor_thread.stop }
    @distributor_threads = nil
  end

  def show_stop_status(num_requests)
    @distributor_threads.to_a.each { |distributor_thread| distributor_thread.show_stop_status(num_requests) }
  end

  class DistributorThread
    def initialize(topic)
      # late include of CelluloidSubscriber because the class is resolved
      # at runtime since we can have different backends.
      extend Promiscuous::Kafka::Subscriber

      @kill_lock = Mutex.new
      @consumer = subscribe(topic)
      @thread = Thread.new { main_loop }
      @thread.abort_on_exception = true

      Promiscuous.debug "[kafka] Subscribing to topic:#{topic} #{@thread}"
    end

    def on_message(metadata, payload)
      Promiscuous.debug "[kafka] [receive] #{payload.value} #{Thread.current}"
      msg = Promiscuous::Subscriber::Message.new(payload.value, :metadata => metadata, :root_worker => @root)
      msg.process
    rescue Exception => e
      Promiscuous.warn "[kafka] [receive] cannot process message: #{e}\n#{e.backtrace.join("\n")}"
      Promiscuous::Config.error_notifier.call(e)
    end

    # TODO: make sure we're on the sync topic(s) as well
    # TODO: add sleep in loop?
    def main_loop
      loop do
        @kill_lock.synchronize do
          fetch_and_process_messages(&method(:on_message))
        end
        sleep 0.2
      end
    end

    def stop
      if @kill_lock.locked? && @thread.stop?
        @thread.kill
      else
        @kill_lock.synchronize { @thread.kill }
      end
    end

    def show_stop_status(num_requests)
      backtrace = @thread.backtrace

      STDERR.puts "Still processing messages (#{num_requests})"

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
