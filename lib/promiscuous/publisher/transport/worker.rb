class Promiscuous::Publisher::Transport::Worker
  def initialize
    @persistence = Promiscuous::Publisher::Transport.persistence
  end

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

        @persistence.expired.each do |id, attributes|
          batch = Promiscuous::Publisher::Transport::Batch.load(id, attributes)
          batch.publish
          Promiscuous.info "[publish][recovery] #{id} recovered: #{attributes}"
        end
      rescue => e
        puts e
        Promiscuous::Config.error_notifier.call(e)
      end
    end
  ensure
    ActiveRecord::Base.clear_active_connections!
  end
end

