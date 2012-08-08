module Replicable
  module Worker
    def self.run
      queue_name = "#{Replicable::AMQP.app}.replicable"

      stop = false
      Replicable::AMQP.subscribe(:queue_name => queue_name,
                                 :bindings   => Replicable::Subscriber::AMQP.subscribers.keys) do |metadata, payload|
        begin
          unless stop
            Replicable::AMQP.info "[receive] #{payload}"
            Replicable::Subscriber.process(JSON.parse(payload))
            metadata.ack
          end
        rescue Exception => e
          e = Replicable::Subscriber::Error.new(e, payload)
          stop = true
          Replicable::AMQP.close
          Replicable::AMQP.error "[receive] FATAL #{e}"
          Replicable::AMQP.error_handler.call(e) if Replicable::AMQP.error_handler
        end
      end
    end
  end
end
