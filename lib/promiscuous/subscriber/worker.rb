class Promiscuous::Subscriber::Worker
  include Promiscuous::Common::Worker

  def replicate
    Promiscuous::AMQP.subscribe(subscribe_options) do |metadata, payload|
      # Note: This code always runs on the root Fiber,
      # so ordering is always preserved
      begin
        unless self.stop
          Promiscuous.info "[receive] #{payload}"
          self.unit_of_work { Promiscuous::Subscriber.process(JSON.parse(payload)) }
          metadata.ack
        end
      rescue Exception => e
        e = Promiscuous::Subscriber::Error.new(e, payload)

        # TODO Discuss with Arjun about having an error queue.
        self.stop = true
        Promiscuous::AMQP.disconnect
        Promiscuous.error "[receive] FATAL #{e} #{e.backtrace.join("\n")}"
        Promiscuous.error "[receive] FATAL #{e}"
        Promiscuous::Config.error_handler.try(:call, e)
      end
    end
  end

  def subscribe_options
    queue_name = "#{Promiscuous::Config.app}.promiscuous"
    bindings = Promiscuous::Subscriber::AMQP.subscribers.keys
    {:queue_name => queue_name, :bindings => bindings}
  end
end
