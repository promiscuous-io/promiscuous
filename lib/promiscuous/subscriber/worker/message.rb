class Promiscuous::Subscriber::Worker::Message
  attr_accessor :metadata, :payload, :parsed_payload

  def initialize(metadata, payload)
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
    return nil unless parsed_payload['version'].is_a? Hash # TODO remove once migrated
    @version ||= parsed_payload['version'].try(:symbolize_keys)
  end

  def global_version
    version.try(:[], :global)
  end

  def has_dependencies?
    return false if Promiscuous::Config.bareback
    !!global_version
  end

  def ack
    EM.next_tick do
      begin
        metadata.ack if metadata.channel.open?
      rescue
        # We don't care if we fail, the message will be redelivered at some point
      end
    end
  end

  def unit_of_work(type, &block)
    # type is used by the new relic agent, by monkey patching.
    # middleware?
    if defined?(Mongoid)
      Mongoid.unit_of_work { yield }
    else
      yield
    end
  ensure
    if defined?(ActiveRecord)
      ActiveRecord::Base.clear_active_connections!
    end
  end

  def process
    #return if worker.stopped?

    Promiscuous.debug "[receive] #{payload}"
    unit_of_work(queue_name) do
      Promiscuous::Subscriber.process(parsed_payload, :message => self)
    end

    ack
  rescue Exception => e
    e = Promiscuous::Error::Subscriber.new(e, :payload => payload)
    Promiscuous.warn "[receive] #{e} #{e.backtrace.join("\n")}"
    Promiscuous::Config.error_notifier.try(:call, e)
  end
end
