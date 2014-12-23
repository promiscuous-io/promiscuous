class Promiscuous::Publisher::Operation::Recovery < Promiscuous::Publisher::Operation::Base
  def recover!(lock)
    @instance = fetch_instance_for_lock_data(lock.data)

    lock_operations_and_queue_recovered_payloads

    publish_payloads_async
  end
end

