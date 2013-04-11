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

  def endpoint
    parsed_payload['__amqp__']
  end

  def publisher_app
    if endpoint =~ /^([^\/]+)\//
      $1
    else
      raise "Invalid endpoint: #{endpoint}"
    end
  end

  def timestamp
    parsed_payload['timestamp'].to_i
  end

  def dependencies
    @dependencies ||= begin
      dependencies = parsed_payload['dependencies'] || {}
      deps = dependencies['read'].to_a.map  { |dep| Promiscuous::Dependency.parse(dep, :type => :read, :publisher_app => publisher_app) } +
             dependencies['write'].to_a.map { |dep| Promiscuous::Dependency.parse(dep, :type => :write, :publisher_app => publisher_app) }

      deps
    end
  end

  def write_dependencies
    @write_dependencies ||= dependencies.select(&:write?)
  end

  def read_dependencies
    @read_dependencies ||= dependencies.select(&:read?)
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
    return false if Promiscuous::Config.no_deps
    dependencies.present?
  end

  def to_s
    "#{endpoint} -> #{happens_before_dependencies.join(', ')}"
  end

  def ack
    time = Time.now
    Promiscuous.debug "[receive] #{payload}"
    @metadata.ack
    @root_worker.stats.notify_processed_message(self, time) if @root_worker
  rescue Exception => e
    # We don't care if we fail, the message will be redelivered at some point
    Promiscuous.warn "[receive] Some exception happened, but it's okay: #{e}\n#{e.backtrace.join("\n")}"
    Promiscuous::Config.error_notifier.call(e)
  end

  def postpone
    # Only used during bootstrapping
    @metadata.postpone
  rescue Exception => e
    # We don't care if we fail
    Promiscuous.warn "[receive] (postpone) Some exception happened, but it's okay: #{e}\n#{e.backtrace.join("\n")}"
    Promiscuous::Config.error_notifier.call(e)
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
    unit_of_work(endpoint) do
      payload = Promiscuous::Subscriber::Payload.new(parsed_payload, self)
      Promiscuous::Subscriber::Operation.new(payload).commit
    end
  rescue Promiscuous::Error::AlreadyProcessed => orig_e
    e = Promiscuous::Error::Subscriber.new(orig_e, :payload => payload)
    Promiscuous.debug "[receive] #{payload} #{e}\n#{e.backtrace.join("\n")}"
  rescue Exception => orig_e
    e = Promiscuous::Error::Subscriber.new(orig_e, :payload => payload)
    Promiscuous.warn "[receive] #{payload} #{e}\n#{e.backtrace.join("\n")}"
    Promiscuous::Config.error_notifier.call(e)
  end
end
