class Promiscuous::Publisher::Operation::Transaction < Promiscuous::Publisher::Operation::Base
  attr_accessor :transaction_id, :transaction_operations

  def initialize(options={})
    super
    @transaction_id = options[:transaction_id]
    @operation_name = :commit
    @transaction_operations = options[:transaction_operations].to_a
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

  def operations
    @transaction_operations
  end

  def execute_instrumented(query)
    lock_operations_and_queue_recovered_payloads

    query.call_and_remember_result(:instrumented)

    queue_operation_payloads

    publish_payloads(:async => true)
  end
end
