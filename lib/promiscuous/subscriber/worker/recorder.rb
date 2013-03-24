class Promiscuous::Subscriber::Worker::Recorder
  include Celluloid

  def initialize(log_file)
    extend Promiscuous::AMQP::CelluloidSubscriber
    @file = File.open(log_file, 'a')

    options = {}
    options[:channel_name] = :pump
    options[:queue_name] = "#{Promiscuous::Config.app}.promiscuous"
    # We need to subscribe to everything to keep up with the version tracking
    options[:bindings] = ['*']

    subscribe(options) do |metadata, payload|
      @file.puts payload
      metadata.ack
    end
  end

  def close_file
    @file.try(:close)
  end
  finalizer :close_file
end
