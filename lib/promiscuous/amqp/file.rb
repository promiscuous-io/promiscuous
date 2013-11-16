class Promiscuous::AMQP::File
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
      file = File.open(Promiscuous::Config.subscriber_amqp_url, 'r')

      @prefetch = Promiscuous::Config.prefetch
      @num_pending = 0
      @lock = Mutex.new
      @prefetch_wait = ConditionVariable.new

      @thread = Thread.new do
        file.each do |line|
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

    def recover
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
