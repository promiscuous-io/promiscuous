class Promiscuous::Subscriber::Worker::Distributor
  def initialize(root)
    @root = root
  end

  def start
    num_threads = Promiscuous::Config.subscriber_threads
    Promiscuous::Config.subscriber_topics.each do |topic|
      @distributor_threads ||= num_threads.times.map { DistributorThread.new(topic) }
      Promiscuous.debug "[distributor] Started #{num_threads} thread#{'s' if num_threads>1} topic:#{topic}"
    end
  end

  def stop
    return unless @distributor_threads
    Promiscuous.debug "[distributor] Stopping #{@distributor_threads.count} threads"

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
      extend Promiscuous::Backend::Poseidon::Subscriber

      @stop = false
      @thread = Thread.new(topic) {|t| main_loop(t) }

      Promiscuous.debug "[distributor] Subscribing to topic:#{topic} [#{@thread.object_id}]"
    end

    def on_message(metadata, payload)
      Promiscuous.debug "[kafka] [receive] #{payload.value} [#{@thread.object_id}]"
      msg = Promiscuous::Subscriber::Message.new(payload.value, :metadata => metadata, :root_worker => @root)
      msg.process
    rescue Exception => e
      Promiscuous.warn "[kafka] [receive] cannot process message: #{e}\n#{e.backtrace.join("\n")}"
      Promiscuous::Config.error_notifier.call(e)
    end

    def main_loop(topic)
      @consumer = subscribe(topic)
      while not @stop do
        begin
          fetch_and_process_messages(&method(:on_message))
        rescue Poseidon::Connection::ConnectionFailedError
          Promiscuous.debug "[kafka] Reconnecting... [#{@thread.object_id}]"
          @consumer = subscribe(@topic)
        end
        sleep 0.1
      end
      @consumer.close if @consumer
      @consumer = nil
    end

    def stop
      Promiscuous.debug "[distributor] stopping status:#{@thread.status} [#{@thread.object_id}]"

      # We wait in case the consumer is responsible for more than one partition
      # see: https://github.com/bsm/poseidon_cluster/blob/master/lib/poseidon/consumer_group.rb#L229
      @stop = true
      @thread.join
      Promiscuous.debug "[distributor] stopped [#{@thread.object_id}]"
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
