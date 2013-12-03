class Promiscuous::Subscriber::Operation::Regular < Promiscuous::Subscriber::Operation::Base
  def execute
    case operation
    when :create  then create  if model
    when :update  then update  if model
    when :destroy then destroy if model
    end
  rescue Exception => e
    if Promiscuous::Config.ignore_exceptions && !e.is_a?(NameError)
      Promiscuous.warn "[receive] error while proceessing message but message still processed: #{e}\n#{e.backtrace.join("\n")}"
    else
      raise e
    end
  end

  def message_processor
    @message_processor ||= Promiscuous::Subscriber::MessageProcessor::Regular.current
  end
end
