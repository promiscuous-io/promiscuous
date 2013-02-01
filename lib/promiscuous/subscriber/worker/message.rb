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

  def has_version?
    !!version
  end

  def version
    @version ||= parsed_payload['version'].try(:symbolize_keys)
  end

  def update_dependencies
    global_key = Promiscuous::Redis.sub_key('global')
    global_version = Promiscuous::Redis.incr global_key
    Promiscuous::Redis.publish(global_key, global_version)
  end

  def process
    return if worker.stopped?

    Promiscuous.debug "[receive] #{payload}"

    worker.unit_of_work(queue_name) { Promiscuous::Subscriber.process(parsed_payload) }

    update_dependencies
    metadata.ack
  rescue Exception => e
    e = Promiscuous::Error::Subscriber.new(e, :payload => payload)
    Promiscuous.warn "[receive] #{e} #{e.backtrace.join("\n")}"
    Promiscuous::Config.error_notifier.try(:call, e)
  end
end
