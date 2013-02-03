class Promiscuous::Subscriber::Worker::Pump
  # TODO Make this celluloid happy
  attr_accessor :worker

  def initialize(worker)
    self.worker = worker
  end

  def start
    return if @queue
    Promiscuous::AMQP.open_queue(queue_bindings) do |queue|
      @queue = queue
      @queue.subscribe :ack => true do |metadata, payload|
        # we drop the payload if we switched to another queue,
        # duplicate messages could hurt us.
        process_payload(metadata, payload) if queue == @queue
      end
    end
  end

  def stop
    queue, @queue = @queue, nil
    queue.unsubscribe if queue rescue nil
  end

  def process_payload(metadata, payload)
    msg = Promiscuous::Subscriber::Worker::Message.new(worker, metadata, payload)
    worker.message_synchronizer.process_when_ready(msg)
  end

  def queue_bindings
    queue_name = "#{Promiscuous::Config.app}.promiscuous"
    exchange_name = Promiscuous::AMQP::EXCHANGE

    if worker.options[:personality]
      queue_name    += ".#{worker.options[:personality]}"
      exchange_name += ".#{worker.options[:personality]}"
    end

    # We need to subscribe to everything to keep up with the version tracking
    bindings = ['*']
    {:exchange_name => exchange_name, :queue_name => queue_name, :bindings => bindings}
  end
end
