class Promiscuous::Subscriber::Worker::Message
  attr_accessor :metadata, :payload, :parsed_payload

  def initialize(metadata, payload)
    self.metadata = metadata
    self.payload = payload
  end

  def parsed_payload
    @parsed_payload ||= JSON.parse(payload)
  end

  def endpoint
    parsed_payload['__amqp__']
  end

  def timestamp
    parsed_payload['timestamp'].to_i
  end

  def dependencies
    return @dependencies if @dependencies
    @dependencies = parsed_payload['dependencies'].try(:symbolize_keys) || {}
    @dependencies[:read]  ||= []
    @dependencies[:write] ||= []

    # --- backward compatiblity code ---
    # TODO remove code
    if global = (parsed_payload['version'] || {})['global']
      @dependencies[:write] << "global:#{global}"
    end
    # --- backward compatiblity code ---

    @dependencies[:link] = Promiscuous::Dependency.from_json(@dependencies[:link]) if @dependencies[:link]
    @dependencies[:read].map!  { |dep| Promiscuous::Dependency.from_json(dep) }
    @dependencies[:write].map! { |dep| Promiscuous::Dependency.from_json(dep) }
    @dependencies
  end

  def happens_before_dependencies
    return @happens_before_dependencies if @happens_before_dependencies

    read_increments = {}
    dependencies[:read].each do |dep|
      key = dep.key(:sub).for(:redis)
      read_increments[key] ||= 0
      read_increments[key] += 1
    end

    deps = []
    deps << dependencies[:link] if dependencies[:link]
    deps += dependencies[:read]
    deps += dependencies[:write].map do |dep|
      dep.dup.tap { |d| d.version -= 1 + read_increments[d.key(:sub).for(:redis)].to_i }
    end

    # We return the most difficult condition to satisfy first
    @happens_before_dependencies = deps.uniq.reverse
  end

  def has_dependencies?
    return false if Promiscuous::Config.bareback
    dependencies[:read].present? || dependencies[:write].present?
  end

  def to_s
    "#{endpoint} -> #{happens_before_dependencies.join(', ')}"
  end

  def ack
    time = Time.now
    metadata.try(:ack)
    Celluloid::Actor[:stats].async.notify_processed_message(self, time)
  rescue
    # We don't care if we fail, the message will be redelivered at some point
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
    Promiscuous.debug "[receive] #{payload}"
    unit_of_work(endpoint) do
      payload = Promiscuous::Subscriber::Payload.new(parsed_payload, self)
      Promiscuous::Subscriber::Operation.new(payload).commit
    end
    ack

  rescue Exception => e
    ack if e.is_a?(Promiscuous::Error::AlreadyProcessed) && Promiscuous::Config.recovery

    e = Promiscuous::Error::Subscriber.new(e, :payload => payload)
    Promiscuous.warn "[receive] #{e} #{e.backtrace.join("\n")}"
    Promiscuous::Config.error_notifier.try(:call, e)
  end
end
