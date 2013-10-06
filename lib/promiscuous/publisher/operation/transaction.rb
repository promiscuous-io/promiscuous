class Promiscuous::Publisher::Operation::Transaction < Promiscuous::Publisher::Operation::Base
  attr_accessor :transaction_id, :transaction_operations, :operation_payloads

  def initialize(options={})
    super
    @operation = :commit
    @transaction_operations = options[:transaction_operations].to_a
    @transaction_id = options[:transaction_id]
    @operation_payloads = options[:operation_payloads]
  end

  def dependency_for_op_lock
    # We don't take locks on rows as the database already have the locks on them
    # until the transaction is committed.
    # A lock on the transaction ID is taken so we know when we conflict with
    # the recovery mechanism.
    Promiscuous::Dependency.new("__transactions__", self.transaction_id, :dont_hash => true)
  end

  def pending_writes
    # TODO (performance) Return a list of writes that:
    # - Never touch the same id (the latest write is sufficient)
    # - create/update and then delete should be invisible
    @transaction_operations
  end

  def query_dependencies
    @query_dependencies ||= pending_writes.map(&:query_dependencies).flatten
  end

  def operation_payloads
    @operation_payloads ||= pending_writes.map(&:operation_payloads).flatten
  end

  alias cache_operation_payloads operation_payloads

  def should_instrument_query?
    super && !pending_writes.empty?
  end

  def execute_instrumented(query)
    unless self.recovering?
      generate_read_dependencies
      acquire_op_lock

      # As opposed to atomic operations, we know the values of the instances
      # before the database operation, and not after, so only one stage
      # of recovery is used.
      cache_operation_payloads

      query.call_and_remember_result(:prepare)
    end

    self.increment_read_and_write_dependencies

    query.call_and_remember_result(:instrumented)

    # We can't do anything if the prepared commit doesn't go through.
    # Either it's a network failure, or the database is having some real
    # difficulties. The recovery mechanism will have to retry the transaction.
    return if query.failed?

    # We take a timestamp right after the write is performed because latency
    # measurements are performed on the subscriber.
    record_timestamp

    ensure_op_still_locked

    generate_payload
    clear_previous_dependencies

    publish_payload_in_redis
    release_op_lock
    publish_payload_in_rabbitmq_async
  end

  def recovery_payload
    # TODO just save the table/ids, or publish the real payload directly.
    [@transaction_id, @operation_payloads]
  end

  def self.recover_operation(transaction_id, operation_payloads)
    new(:transaction_id => transaction_id, :operation_payloads => operation_payloads)
  end
end
