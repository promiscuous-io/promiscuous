class Promiscuous::Subscriber::Worker::Pump
  attr_accessor :worker

  def initialize(worker)
    self.worker = worker
  end

  def resume
    if @queue
      # XXX TODO we should not access to the channel like this.
      # The abstraction is leaking.
      # Actually, we actually want one channel per worker.

      # The following tells rabbitmq to resend the unacked messages
      Promiscuous::AMQP::RubyAMQP.channel.recover
    else
      Promiscuous::AMQP.open_queue(queue_bindings) do |queue|
        @queue = queue
        @queue.subscribe({:ack => true}, &method(:process_payload))
      end
    end
  end

  def stop
    # we should tell amqp that we want to stop using the queue
  end

  def process_payload(metadata, payload)
    return if worker.stopped?

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

    bindings = Promiscuous::Subscriber::AMQP.subscribers.keys
    {:exchange_name => exchange_name, :queue_name => queue_name, :bindings => bindings}
  end
end
