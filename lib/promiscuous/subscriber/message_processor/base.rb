class Promiscuous::Subscriber::MessageProcessor::Base
  attr_accessor :message

  def initialize(message)
    self.message = message
  end

  def operations
    message.parsed_payload['operations'].map { |op| operation_class.new(op) }
  end

  def self.process(*args)
    raise "Same thread is processing a message?" if self.current

    begin
      self.current = new(*args)
      self.current.process_message
    ensure
      self.current = nil
    end
  end

  def self.current
    Thread.current[:promiscuous_message_processor]
  end

  def self.current=(value)
    Thread.current[:promiscuous_message_processor] = value
  end

  def process_message
    begin
      on_message
    rescue Exception => e
      raise e if e.is_a?(Promiscuous::Error::AlreadyProcessed) || e.is_a?(NameError)

      @fail_count ||= 0;  @fail_count += 1

      if @fail_count <= Promiscuous::Config.max_retries
        sleep @fail_count ** 2

        unless e.is_a?(Promiscuous::Error::Retry)
          Promiscuous::Config.error_notifier.call(e) if @fail_count == 1
        end
        Promiscuous.warn("[recieve] retry [#{@fail_count}]: #{@message}")

        process_message
      else
        raise e
      end
    end
  end

  def on_message
    raise "Must be implemented"
  end

  def operation_class
    raise "Must be implemented"
  end
end
