module Promiscuous
  module Worker
    def self.replicate
      queue_name = "#{Promiscuous::AMQP.app}.promiscuous"
      bindings = Promiscuous::Subscriber.subscribers.keys

      stop = false
      Promiscuous::AMQP.subscribe(:queue_name => queue_name, :bindings => bindings) do |metadata, payload|
        begin
          unless stop
            Promiscuous::AMQP.info "[receive] #{payload}"
            Promiscuous::Subscriber.process(JSON.parse(payload))
            metadata.ack
          end
        rescue Exception => e
          e = Promiscuous::Subscriber::Error.new(e, payload)
          stop = true
          Promiscuous::AMQP.close
          Promiscuous::AMQP.error "[receive] FATAL #{e}"
          Promiscuous::AMQP.error_handler.call(e) if Promiscuous::AMQP.error_handler
        end
      end
    end
  end
end
