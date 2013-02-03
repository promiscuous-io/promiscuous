class Promiscuous::Subscriber::Worker::Message
  attr_accessor :worker, :metadata, :payload, :parsed_payload

  def initialize(worker, metadata, payload)
    self.worker = worker
    self.metadata = metadata
    self.payload = payload
  end

  def parsed_payload
    @parsed_payload ||= JSON.parse(payload)
  end

  def queue_name
    parsed_payload['__amqp__']
  end

  def version
    @version ||= parsed_payload['version'].try(:symbolize_keys)
  end

  def global_version
    version.try(:[], :global)
  end

  def has_dependencies?
    !!global_version
  end

  def ack
    EM.next_tick do
      begin
        metadata.ack
      rescue
        # We don't care if we fail, the message will be redelivered at some point
      end
    end
  end

  def process
    return if worker.stopped?

    Promiscuous.debug "[receive] #{payload}"
    worker.unit_of_work(queue_name) do
      Promiscuous::Subscriber.process(parsed_payload, :message => self)
    end

    ack
  rescue Exception => e
    e = Promiscuous::Error::Subscriber.new(e, :payload => payload)
    Promiscuous.warn "[receive] #{e} #{e.backtrace.join("\n")}"
    Promiscuous::Config.error_notifier.try(:call, e)
  end
end
