class Promiscuous::Publisher::Operation::Transaction < Promiscuous::Publisher::Operation::Base
  attr_accessor :transaction_id

  def initialize(options={})
    super
    @operation = :commit
    @transaction_operations = options[:transaction_operations] || []
    @connection = options[:connection]
    @transaction_id = options[:transaction_id] || @connection.current_transaction_id
    @document_payloads = options[:document_payloads]
    @operation_payloads = options[:operation_payloads]
  end

  def nop?
    # Don't do anything fancy if we have no operations to deal with
    pending_writes.empty?
  end

  def pending_writes
    # TODO (performance) Return a list of writes that:
    # - Never touch the same id (the latest write is sufficient)
    # - create/update and then delete should be invisible
    @pending_writes ||= @transaction_operations.select(&:write?).select(&:pending?)
  end

  def dependency_for_op_lock
    # We don't take locks on rows as the database already have the locks on them
    # until the transaction is committed.
    # A lock on the transaction ID is taken so we know when we conflict with
    # the recovery mechanism.
    Promiscuous::Dependency.new("__transactions__", self.transaction_id, :dont_hash => true)
  end

  def query_dependencies
    @query_dependencies ||= pending_writes.map(&:query_dependencies).flatten
  end

  def operation_payloads
    @operation_payloads ||= pending_writes.map(&:operation_payloads).flatten
  end

  alias cache_operation_payloads operation_payloads

  def prepare_db_transaction
    @connection.prepare_db_transaction
  end

  def commit_db_transaction
    @connection.commit_prepared_db_transaction(@transaction_id)
  end

  def rollback_db_transaction
    @connection.rollback_prepared_db_transaction(@transaction_id)
  end

  def execute_persistent_locked(&db_operation)
    # As opposed to atomic operations, we know the values of the instances
    # before the database operation, and not after, so only one stage
    # of recovery is used.
    cache_operation_payloads

    prepare_db_transaction unless self.recovering?

    self.increment_read_and_write_dependencies

    perform_db_operation_with_no_exceptions do
      # We don't use the original db_operation, we do a 2pc on the db.
      commit_db_transaction
    end

    # We don't know what to do if the commit fails. It's not supposed to.
    return if failed?

    # We take a timestamp right after the write is performed because latency
    # measurements are performed on the subscriber.
    record_timestamp

    ensure_op_still_locked

    generate_payload
    clear_previous_operations

    publish_payload_in_redis
    release_op_lock
    publish_payload_in_rabbitmq_async
  end

  def recovery_payload
    # TODO just save the table/ids, or publish the real payload directly.
    [@transaction_id, @operation_payloads]
  end

  def self.recover_operation(transaction_id, operation_payloads)
    new(:transaction_id => transaction_id, :operation_payloads => operation_payloads, :state => :recovering)
  end
end
