require 'robust-redis-lock'

class Promiscuous::Publisher::Operation::Base
  attr_accessor :operation_name, :recovering, :routing, :exchange, :operations, :instance

  def initialize(options={})
    @operation_name = options[:operation_name]
    @instance       = options[:instance]
    @operation_payloads = [];  @locks = []
  end

  def operations
    [self]
  end

  def record_timestamp
    # Records the number of milliseconds since epoch, which we use send sending
    # the payload over. It's good for latency measurements.
    time = Time.now
    @timestamp = time.to_i * 1000 + time.usec / 1000
  end

  def should_instrument_query?
    !Promiscuous.disabled?
  end

  def execute(&query_config)
    query = Promiscuous::Publisher::Operation::ProxyForQuery.new(self, &query_config)

    if should_instrument_query?
      execute_instrumented(query)
    else
      query.call_and_remember_result(:non_instrumented)
    end

    query.result
  end

  def execute_instrumented(db_operation)
    # Implemented by subclasses
    raise
  end

  def trace_operation
    if ENV['TRACE']
      msg = self.explain_operation(70)
      Promiscuous.context.trace(msg, :color => '1;31')
    end
  end

  def explain_operation(max_width)
    "Unknown database operation"
  end

  def payload_attributes
    if current_user = Promiscuous.context.current_user
      { :current_user_id => current_user.id }
    else
      {}
    end
  end

  def lock_operations_and_queue_recovered_payloads
    operations.map { |operation| [operation.instance.promiscuous.key, operation] }.
      sort { |a,b| a[0] <=> b[0] }.each do |instance_key, operation|
      lock_data = { :type               => operation.operation_name,
                    :payload_attributes => self.payload_attributes,
                    :class              => operation.instance.class.to_s,
                    :id                 => operation.instance.id.to_s }
      @locks << Redis::Lock.new(Promiscuous::Key.new(:pub).join(instance_key).to_s,
                                lock_data,
                                lock_options.merge(:redis => redis))

      @locks.each do |lock|
        case lock.lock
        when true
          # All good
        when false
          unlock_all_locks
          raise Promiscuous::Error::LockUnavailable.new(lock.key)
        when :recovered
          recover_for_lock(lock)
          lock.extend
        end
      end
    end
  end

  def recover_for_lock(lock)
    operation = self.class.new(:instance => fetch_instance_for_lock(lock), :operation_name => lock.data[:type])
    queue_operation_payloads([operation])
  end

  def fetch_instance_for_lock(lock)
    klass = lock.data[:class].constantize
    if lock.data[:type] == :destroy
      klass.new.tap { |new_instance| new_instance.id = lock.data[:id] }
    else
      klass.where(:id => lock.data[:id]).first
    end
  end

  def unlock_all_locks
    @locks.each(&:unlock)
  end

  def queue_operation_payloads(operations = self.operations)
    # XXX Store in hash by KEY so that messages are aggregated per doc
    @operation_payloads += operations.
      map { |operation| operation.instance.promiscuous.payload(:with_attributes => operation.operation_name != :destroy).
            merge(:operation => operation.operation_name, :version => operation.instance.attributes[Promiscuous::Config.version_field]) if operation.instance }.compact
  end

  def payload
    payload              = {}
    payload[:operations] = @operation_payloads
    payload[:app]        = Promiscuous::Config.app
    payload[:timestamp]  = Time.now
    payload[:generation] = Promiscuous::Config.generation
    payload[:host]       = Socket.gethostname
    payload.merge!(self.payload_attributes)
    MultiJson.dump(payload)
  end

  def publish_payloads_async(options={})
    unlock_all_locks and return if @operation_payloads.blank?

    exchange    = options[:exchange]  || Promiscuous::Config.publisher_exchange
    routing     = options[:routing]   || Promiscuous::Config.sync_all_routing
    raise_error = options[:raise_error].present? ? options[:raise_error] : false

    begin
      Promiscuous::AMQP.publish(:exchange => exchange.to_s,
                                :key => routing.to_s,
                                :payload => payload,
                                :on_confirm => method(:unlock_all_locks))
    rescue Exception => e
      Promiscuous.warn("[publish] Failure publishing to rabbit #{e}\n#{e.backtrace.join("\n")}")
      e = Promiscuous::Error::Publisher.new(e, :payload => payload)
      Promiscuous::Config.error_notifier.call(e)

      raise e.inner if raise_error
    end
  end

  def self.expired
    Redis::Lock.expired(lock_options.merge(:redis => redis))
  end

  def redis
    self.class.redis
  end

  def self.redis
    Promiscuous.ensure_connected
    Promiscuous::Redis.connection
  end

  def self.lock_options
    { :timeout => Promiscuous::Config.publisher_lock_timeout.seconds,
      :sleep   => 0.01,
      :expire  => Promiscuous::Config.publisher_lock_expiration.seconds,
      :key_group => :pub }
  end

  def lock_options
    self.class.lock_options
  end
end
