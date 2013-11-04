class Promiscuous::Subscriber::MessageProcessor::Bootstrap < Promiscuous::Subscriber::MessageProcessor::Base
  def on_message
    if bootstrap_operation?
      operations.each(&:execute)
    else
      # Postpone message by doing nothing
    end
  end

  def bootstrap_operation?
    operations.first.try(:operation) =~ /bootstrap/
  end

  def operation_class
    Promiscuous::Subscriber::Operation::Bootstrap
  end
end
