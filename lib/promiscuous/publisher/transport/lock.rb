class Promiscuous::Publisher::Transport::Lock
  def self.lock_options
    { :timeout => Promiscuous::Config.publisher_lock_timeout.seconds,
      :sleep   => 0.01,
      :expire  => Promiscuous::Config.publisher_lock_expiration.seconds,
      :key_group => :pub }
  end

  def initialize(batch)
    @locks = []

    # XXX This complexity can be removed by changing payloads to assume only one
    # instance per payload
    batch.operations.
      map { |operation| operation.instances.map { |instance| [operation, instance] } }.
      map(&:first).
      map { |operation, instance| [instance.promiscuous.key, instance, operation] }.
      sort { |a,b| a[0] <=> b[0] }.each do |instance_key, instance, operation|

        lock_data = { :type => operation.type,
                      :payload_attributes => batch.payload_attributes,
                      :class => instance.class.to_s,
                      :id => instance.id.to_s }
        # TODO use Key class
        @locks << Redis::Lock.new(Promiscuous::Key.new(:pub).join(instance_key).to_s,
                                  lock_data,
                                  self.class.lock_options.merge(:redis => redis))
      end

    @locks.each do |lock|
      case lock.lock
      when true
        puts "LOCK"
        # All good
      when false
        puts "NOPE"
        unlock
        raise Promiscuous::Error::LockUnavailable.new(lock.key)
      when :recovered
        puts "RECOVERED"
        Promiscuous::Publisher::Transport::Worker.new.recover_expired(lock, false)
        lock.extend
      end
    end
  end

  def unlock
    @locks.each(&:unlock)
  end

  def to_s
    @locks.map { |lock| lock.key }.join(",")
  end

  private

  def redis
    Promiscuous.ensure_connected
    Promiscuous::Redis.connection
  end
end
