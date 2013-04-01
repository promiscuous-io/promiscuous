class Promiscuous::Subscriber::Worker::Pump
  def initialize(root)
    @root = root
    # late include of CelluloidSubscriber because the class is resolved
    # at runtime since we can have different backends.
    extend Promiscuous::AMQP::Subscriber
  end

  def connect
    options = {}
    options[:queue_name] = ENV['QUEUE_NAME'] || "#{Promiscuous::Config.app}.promiscuous"
    # We need to subscribe to everything to keep up with the version tracking
    options[:bindings] = ['*']
    subscribe(options, &method(:on_message))
  end

  def on_message(metadata, payload)
    msg = Promiscuous::Subscriber::Worker::Message.new(payload, :metadata => metadata, :root_worker => @root)
    @root.message_synchronizer.process_when_ready(msg)
  rescue Exception => e
    Promiscuous.warn "[receive] cannot process message: #{e} #{e.backtrace.join("\n")}"
    Promiscuous::Config.error_notifier.try(:call, e)
  end
end
