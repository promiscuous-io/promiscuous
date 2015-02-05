class Promiscuous::Subscriber::Worker::Recorder
  def initialize(log_file)
    @log_file = log_file
    extend Promiscuous::Backend.subscriber_class
  end

  def start
    @file = File.open(@log_file, 'a')

    subscribe do |metadata, payload|
      @file.puts payload
      metadata.ack
    end
  end

  def stop
    disconnect
    @file.try(:close)
  end
end
