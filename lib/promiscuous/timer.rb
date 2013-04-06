class Promiscuous::Timer
  def initialize(name, duration, &block)
    @name = name
    @duration = duration.to_f
    @block = block
    @lock = Mutex.new
  end

  def run_callback
    @block.call
  rescue Exception => e
    # Report the exception only once
    unless @last_exception == e.to_s
      @last_exception = e.to_s
      Promiscuous.warn "[#{@name}] #{e}"
      Promiscuous::Config.error_notifier.try(:call, e)
    end
  end

  def main_loop(options={})
    options = options.dup

    loop do
      sleep @duration unless options.delete(:run_immediately)
      @lock.synchronize do
        return unless @thread
        run_callback
      end
    end
  end

  def start(options={})
    @lock.synchronize do
      @thread ||= Thread.new { main_loop(options) }
    end
  end

  def reset
    if @thread == Thread.current
      # We already hold the lock (the callback called reset)
      @thread = nil
    else
      @lock.synchronize do
        @thread.try(:kill)
        @thread = nil
      end
    end
    @last_exception = nil
  end
end
