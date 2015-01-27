class Promiscuous::Publisher::Operation::Recovery < Promiscuous::Publisher::Operation::Base
  def initialize(options)
    super
    @locks = [options[:lock]]
  end

  def recover!
    @locks.each do |lock|
      lock.extend
      recover_for_lock(lock)
      publish_payloads
    end
  end

  def recover_for_lock(lock)
    recovery_data = YAML.load(lock.recovery_data)
    operation = Promiscuous::Publisher::Operation::NonPersistent.new(:instance => fetch_instance_for_lock_data(recovery_data),
                                                                     :operation_name => recovery_data[:type])
    queue_operation_payloads([operation])
  end

  def fetch_instance_for_lock_data(lock_data)
    klass = lock_data[:class].constantize
    if lock_data[:type] == :destroy
      klass.new.tap { |new_instance| new_instance.id = lock_data[:id] }
    else
      klass.where(:id => lock_data[:id]).first
    end
  end
end

