class Promiscuous::Subscriber::Worker::Recorder
  def initialize(log_file)
    @log_file = log_file
    extend Promiscuous::AMQP::Subscriber
  end

  def start
    @file = File.open(@log_file, 'a')
    options = {}
    options[:queue_name] = "#{Promiscuous::Config.app}.promiscuous"
    # We need to subscribe to everything to keep up with the version tracking
    options[:bindings] = ['*']

    subscribe(options) do |metadata, payload|
      @file.puts payload
      metadata.ack
    end
  end

  def stop
    disconnect
    @file.try(:close)
  end
end
