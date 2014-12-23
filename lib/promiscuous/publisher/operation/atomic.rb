class Promiscuous::Publisher::Operation::Atomic < Promiscuous::Publisher::Operation::Base
  # XXX instance can be a selector representation.
  attr_accessor :instance

  def instances
    [@instance].compact
  end

  def execute_instrumented(query)
    if operation_name == :destroy
      fetch_instance
    else
      increment_version_in_document
    end

    lock_instances_and_queue_recovered_payloads

    query.call_and_remember_result(:instrumented)

    queue_instance_payloads

    publish_payloads_async
  end

  def increment_version_in_document
    raise
  end
end
