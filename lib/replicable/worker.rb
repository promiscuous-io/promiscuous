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
      subscriber_class = bindings_map[binding]

      raise "FATAL: Unknown binding: '#{binding}'" if subscriber_class.nil?
      self.process_for(subscriber_class, amqp_payload)
    end

    def self.process_for(subscriber_class, amqp_payload)
      id = amqp_payload[:id]

      subscriber = subscriber_class.new
      subscriber.type = amqp_payload[:type]
      subscriber.operation = amqp_payload[:operation].to_sym

      model = subscriber.model
      instance = case subscriber.operation
      when :create
        model.new
      when :update
        model.find(id)
      when :destroy
        model.find(id)
      end

      instance.id = id
      subscriber.instance = instance
      subscriber.replicate(amqp_payload[:payload].symbolize_keys)

      case subscriber.operation
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
