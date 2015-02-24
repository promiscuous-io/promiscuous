class Promiscuous::Subscriber::Message
  attr_accessor :payload, :parsed_payload

  def initialize(payload, options={})
    self.payload = payload
    @metadata = options[:metadata]
    @root_worker = options[:root_worker]
  end

  def parsed_payload
    @parsed_payload ||= if payload.is_a?(Hash)
      payload.with_indifferent_access
    else
      MultiJson.load(payload)
    end
  end

  def app
    parsed_payload['app']
  end

  def timestamp
    parsed_payload['timestamp'].to_i
  end

  def generation
    parsed_payload['generation'] || 0
  end

  def types
    @parsed_payload['types']
  end

  def to_s
    "#{app} -> #{types}"
  end

  def ack
    time = Time.now
    Promiscuous.debug "[receive] #{payload}"
    @metadata.try(:ack)
    @root_worker.stats.notify_processed_message(self, time) if @root_worker
  rescue Exception => e
    # We don't care if we fail, the message will be redelivered at some point
    Promiscuous.warn "[receive] Some exception happened, but it's okay: #{e}\n#{e.backtrace.join("\n")}"
    Promiscuous::Config.error_notifier.call(e)
  end

  def nack
    Promiscuous.debug "[receive][failed] #{payload}"
    @metadata.try(:nack)
  rescue Exception => e
    # We don't care if we fail, the message will be redelivered at some point
    Promiscuous.warn "[receive] Some exception happened, but it's okay: #{e}\n#{e.backtrace.join("\n")}"
    Promiscuous::Config.error_notifier.call(e)
  end

  def process
    Promiscuous::Backend.process_message(self)
  rescue Exception => orig_e
    e = Promiscuous::Error::Subscriber.new(orig_e, :payload => payload)
    Promiscuous.warn "[receive] #{payload} #{e}\n#{e.backtrace.join("\n")}"
    Promiscuous::Config.error_notifier.call(e)
  ensure
    if defined?(ActiveRecord)
      ActiveRecord::Base.clear_active_connections!
    end
  end
end
