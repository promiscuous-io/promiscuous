class Promiscuous::Subscriber::Worker::Pump
  include Celluloid

  def initialize
    # late include of CelluloidSubscriber because the class is resolved
    # at runtime since we can have different backends.
    extend Promiscuous::AMQP::CelluloidSubscriber

    options = {}
    options[:channel_name] = :pump
    options[:queue_name] = "#{Promiscuous::Config.app}.promiscuous"
    # We need to subscribe to everything to keep up with the version tracking
    options[:bindings] = ['*']

    subscribe(options) do |metadata, payload|
      msg = Promiscuous::Subscriber::Worker::Message.new(metadata, payload)
      Celluloid::Actor[:message_synchronizer].process_when_ready(msg)
    end
  end
end
