class Promiscuous::Publisher::Operation::Atomic < Promiscuous::Publisher::Operation::Base
  def execute_instrumented(query)
    if operation_name == :destroy
      fetch_instance
    else
      increment_version_in_document
    end

    lock_operations_and_queue_recovered_payloads
    query.call_and_remember_result(:instrumented)

    unless query.failed?
      queue_operation_payloads
      publish_payloads(:async => true)
    end
  end

  def increment_version_in_document
    raise
  end
end
