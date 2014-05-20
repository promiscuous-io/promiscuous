class Promiscuous::Publisher::Operation::Base
  attr_accessor :operation, :recovering

  def initialize(options={})
    @operation = options[:operation]
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

  def create_transport_batch(operations)
    Promiscuous::Publisher::Transport::Batch.new.tap do |batch|
      operations.map do |operation|
        batch.add operation.operation, operation.instances
      end

      if current_user = Promiscuous.context.current_user
        batch.payload_attributes = { :current_user_id => current_user.id }
      end
    end
  end
end
