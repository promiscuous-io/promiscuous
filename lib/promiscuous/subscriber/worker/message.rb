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

  def has_global_version?
    !!global_version
  end

  def update_dependencies
    if has_global_version?
      global_key = Promiscuous::Redis.sub_key('global')
      # Note that we do not use incr to avoid out of sync versions
      # The message sychnronizer enforces the global version with ==
      Promiscuous::Redis.set(global_key, global_version)
      Promiscuous::Redis.publish(global_key, global_version)
    end
  end

  def process
    return if worker.stopped?

    Promiscuous.debug "[receive] #{payload}"

    worker.unit_of_work(queue_name) { Promiscuous::Subscriber.process(parsed_payload) }

    update_dependencies
    EM.next_tick { metadata.ack }
  rescue Exception => e
    e = Promiscuous::Error::Subscriber.new(e, :payload => payload)
    Promiscuous.warn "[receive] #{e} #{e.backtrace.join("\n")}"
    Promiscuous::Config.error_notifier.try(:call, e)
  end
end
