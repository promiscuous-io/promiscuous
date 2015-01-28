class Promiscuous::Kafka::File
  def connect
  end

  def disconnect
  end

  def connected?
    true
  end

  def new_connection(options={})
  end

  def publish(options={})
    options[:on_confirm].try(:call)
    raise NotImplemented
  end

  module Subscriber
    attr_accessor :lock, :prefetch_wait, :num_pending

    def subscribe(options={}, &block)
      file_name, worker_index, num_workers = Promiscuous::Config.subscriber_amqp_url.split(':')

      worker_index = worker_index.to_i
      num_workers = num_workers.to_i

      file = File.open(file_name, 'r')

      @prefetch = Promiscuous::Config.prefetch
      @num_pending = 0
      @lock = Mutex.new
      @prefetch_wait = ConditionVariable.new

      @thread = Thread.new do
        file.each_with_index do |line, i|
          if num_workers > 0
            next if ((i+worker_index) % num_workers) != 0
          end

          return if @stop

          @lock.synchronize do
            @prefetch_wait.wait(@lock) until @num_pending < @prefetch
            @num_pending += 1
          end

          block.call(Metadata.new(self), line.chomp)
        end

        @lock.synchronize do
          @prefetch_wait.wait(@lock) until @num_pending == 0
        end

        # will shutdown the CLI gracefully
        Process.kill("SIGTERM", Process.pid)
      end
    end

    def disconnect
      @stop = true
    end

    class Metadata
      def initialize(sub)
        @sub = sub
      end

      def ack
        @sub.lock.synchronize do
          @sub.num_pending -= 1
          @sub.prefetch_wait.signal
        end
      end
    end
  end
end
