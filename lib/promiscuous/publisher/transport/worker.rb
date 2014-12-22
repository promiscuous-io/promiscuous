class Promiscuous::Publisher::Transport::Worker
  def start
    @thread ||= Thread.new { main_loop }
  end

  def stop
    @stop = true
    sleep 0.1
    @thread.kill
  end

  def main_loop
    loop do
      begin
        sleep Promiscuous::Config.recovery_interval

        break if @stop

        recover
      end
    end
  ensure
    ActiveRecord::Base.clear_active_connections!
  end

  def recover
    Promiscuous::Publisher::Transport.expired.each do |lock|
      recover_expired(lock)
    end
  end

  def recover_expired(lock, take_lock=true)
    transport_batch = Promiscuous::Publisher::Transport::Batch.new(:payload_attributes => lock.data[:payload_attributes])
    transport_batch.add(lock.data[:type], [fetch_instance(lock.data)])
    if take_lock
      transport_batch.lock
    end
    transport_batch.publish
    Promiscuous.info "[publish][recovery] #{lock.key} recovered"
  rescue Promiscuous::Error::LockUnavailable => e
    # this is expected from within recovery
  rescue => e
    puts e; puts e.backtrace.join("\n")
    Promiscuous::Config.error_notifier.call(e)
  end

  private

  def fetch_instance(attrs)
    klass = attrs[:class].constantize
    if attrs[:type] == :destroy
      klass.new.tap { |new_instance| new_instance.id = attrs[:id] }
    else
      klass.where(:id => attrs[:id]).first
    end
  end
end

