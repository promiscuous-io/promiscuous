class Promiscuous::Subscriber::Operation::Regular < Promiscuous::Subscriber::Operation::Base
  def execute
    case operation
    when :create  then create  if model
    when :update  then update  if model
    when :destroy then destroy if model
    end
  end

  def message_processor
    @message_processor ||= Promiscuous::Subscriber::MessageProcessor::Regular.current
  end
end
