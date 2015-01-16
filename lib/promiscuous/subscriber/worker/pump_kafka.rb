class Promiscuous::Subscriber::Worker::PumpKafka
  def initialize(root)
    @root = root
    # late include of CelluloidSubscriber because the class is resolved
    # at runtime since we can have different backends.
    extend Promiscuous::Kafka::Subscriber
  end

  # TODO: make sure we're on the sync topic(s) as well
  def connect
    subscribe(&method(:on_message))
  end

  def on_message(metadata, payload)
    msg = Promiscuous::Subscriber::Message.new(payload, :metadata => metadata, :root_worker => @root)
    @root.runner.messages_to_process << msg
  rescue Exception => e
    Promiscuous.warn "[receive] cannot process message: #{e}\n#{e.backtrace.join("\n")}"
    Promiscuous::Config.error_notifier.call(e)
  end
end
