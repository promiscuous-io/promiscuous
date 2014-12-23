class Promiscuous::Publisher::Operation::Recovery < Promiscuous::Publisher::Operation::Base
  def recover!(lock)
    self.instances = [fetch_instance_for_lock(lock)]

    lock_instances_and_queue_recovered_payloads

    queue_instance_payloads

    publish_payloads_async
  end
end

