class Promiscuous::Subscriber::Worker::Message
  attr_accessor :payload, :parsed_payload

  def initialize(payload, options={})
    self.payload = payload
    @metadata = options[:metadata]
    @root_worker = options[:root_worker]
  end

  def parsed_payload
    @parsed_payload ||= MultiJson.load(payload)
  end

  def app
    parsed_payload['app']
  end

  def timestamp
    parsed_payload['timestamp'].to_i
  end

  def generation
    parsed_payload['generation']
  end

  def dependencies
    @dependencies ||= begin
      dependencies = parsed_payload['dependencies'] || {}
      deps = dependencies['write'].to_a.map { |dep| Promiscuous::Dependency.parse(dep, :type => :write, :owner => app) }

      deps
    end
  end

  def types
    @parsed_payload['types']
  end

  def write_dependencies
    @write_dependencies ||= dependencies.select(&:write?)
  end

  def happens_before_dependencies
    @happens_before_dependencies ||= begin
      deps = []
      deps += read_dependencies
      deps += write_dependencies.map { |dep| dep.dup.tap { |d| d.version -= 1 } }

      # We return the most difficult condition to satisfy first
      deps.uniq.reverse
    end
  end

  def has_dependencies?
    dependencies.present?
  end

  def to_s
    "#{app} -> #{write_dependencies.join(', ')}"
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

  def process
    Promiscuous::Subscriber::MessageProcessor.process(self)
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
