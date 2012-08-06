module Replicable
  module Worker
    mattr_accessor :bindings_map

    def self.prepare_bindings
      self.bindings_map = {}
      Replicable::Subscriber.subscriptions.each do |subscriber|
        self.bindings_map[subscriber.binding] = subscriber
      end
    end

    def self.run
      prepare_bindings
      queue_name = "#{Replicable::AMQP.app}.replicable"

      stop = false
      Replicable::AMQP.subscribe(:queue_name => queue_name,
                                 :bindings => bindings_map.keys) do |metadata, payload|
        begin
          unless stop
            Replicable::AMQP.info "[receive] #{payload}"
            self.process(JSON.parse(payload).symbolize_keys)
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

    def self.process(amqp_payload)
      binding = amqp_payload[:binding]
      deserializer = bindings_map[binding]

      raise "FATAL: Unknown binding: '#{binding}'" if deserializer.nil?
      self.process_for(deserializer, amqp_payload)
    end

    def self.process_for(deserializer, amqp_payload)
      id = amqp_payload[:id]
      operation = amqp_payload[:operation].to_sym

      instance = case operation
      when :create
        deserializer.model.new
      when :update
        deserializer.model.find(id)
      when :destroy
        deserializer.model.find(id)
      end

      instance.id = id
      deserializer.new(instance, operation).replicate(amqp_payload[:payload].symbolize_keys)

      case operation
      when :create
        instance.save
      when :update
        instance.save
      when :destroy
        instance.destroy
      end

    end
  end
end
