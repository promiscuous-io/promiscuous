class Promiscuous::Publisher::Operation::Transaction < Promiscuous::Publisher::Operation::Base
  attr_accessor :transaction_id, :transaction_operations

  def initialize(options={})
    super
    @operation = :commit
    @transaction_operations = options[:transaction_operations].to_a
    @transaction_id = options[:transaction_id]
    @operation_payloads = options[:operation_payloads]
  end

  def pending_writes
    # TODO (performance) Return a list of writes that:
    # - Never touch the same id (the latest write is sufficient)
    # - create/update and then delete should be invisible
    @transaction_operations
  end

  def should_instrument_query?
    super && !pending_writes.empty?
  end

  def execute_instrumented(query)
    transport_batch = create_transport_batch(@transaction_operations)
    transport_batch.prepare

    query.call_and_remember_result(:instrumented)

    transport_batch.publish
  end
end
