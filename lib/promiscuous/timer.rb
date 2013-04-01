class Promiscuous::Timer
  def initialize
    @lock = Mutex.new
  end

  def run_every(duration, options={}, &block)
    options = options.dup
    duration = duration.to_f unless duration.is_a?(Integer)
    reset

    @lock.synchronize do
      @thread ||= Thread.new do
        loop do
          sleep duration unless options.delete(:run_immediately)
          @lock.synchronize do
            if @thread == Thread.current
              begin
                block.call
              rescue Exception
              end
            end
          end
        end
      end
    end
  end

  def reset
    if @thread == Thread.current
      @thread = nil
    else
      @lock.synchronize do
        @thread.try(:kill)
        @thread = nil
      end
    end
  end
end
