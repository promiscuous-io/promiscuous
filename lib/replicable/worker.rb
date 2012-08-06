module Replicable
  module Worker
    def self.run
      Replicable::Subscriber.prepare_bindings
      queue_name = "#{Replicable::AMQP.app}.replicable"

      stop = false
      Replicable::AMQP.subscribe(:queue_name => queue_name,
                                 :bindings   => Replicable::Subscriber.binding_map.keys) do |metadata, payload|
        begin
          unless stop
            Replicable::AMQP.info "[receive] #{payload}"
            Replicable::Subscriber.process(JSON.parse(payload))
            metadata.ack
          end
        rescue Exception => e
          stop = true
          Replicable::AMQP.close
          Replicable::AMQP.error "[receive] cannot process #{payload} because #{e}"
          Replicable::AMQP.error_handler.call(e) if Replicable::AMQP.error_handler
        end
      end
    end
  end
end
