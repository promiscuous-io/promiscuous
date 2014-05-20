class Promiscuous::Publisher::Operation::Atomic < Promiscuous::Publisher::Operation::Base
  # XXX instance can be a selector representation.
  attr_accessor :instance

  def instances
    [@instance].compact
  end

  def execute_instrumented(query)
    if operation == :destroy
      fetch_instance
    else
      increment_version_in_document
    end

    transport_batch = create_transport_batch([self])
    transport_batch.prepare

    query.call_and_remember_result(:instrumented)

    unless operation == :destroy
      # Refresh the operation on the batch to include the updated instance
      # reflecting the executed operation so that we publish the correct data.
      transport_batch.clear
      transport_batch.add query.operation.operation, query.operation.instances
    end

    transport_batch.publish
  end

  def increment_version_in_document
    raise
  end
end
