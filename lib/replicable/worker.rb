module Replicable
  module Worker
    mattr_accessor :deserializer_map

    def self.prepare_deserializer_map
      self.deserializer_map = {}
      Replicable::Subscriber.subscriptions.each do |subscriber|
        self.deserializer_map[subscriber.from_class] = subscriber
        self.deserializer_map[subscriber.from_class] = subscriber
      end
    end

    def self.bindings
      Replicable::Subscriber.subscriptions.map { |sub| sub.amqp_binding }
    end

    def self.run
      prepare_deserializer_map
      queue_name = "#{Replicable::AMQP.app}.replicable"

      stop = false
      Replicable::AMQP.subscribe(:queue_name => queue_name, :bindings => bindings) do |metadata, payload|
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
      from_class = amqp_payload[:classes].last
      deserializer_class = deserializer_map[from_class]

      raise "Unknown incoming class: '#{from_class}'" if deserializer_class.nil?
      self.process_for(deserializer_class, amqp_payload)
    end

    def self.process_for(deserializer_class, amqp_payload)
      id = amqp_payload[:id]
      operation = amqp_payload[:operation].to_sym
      klass = deserializer_class.model.to_s.camelize.constantize

      instance = case operation
      when :create
        klass.new
      when :update
        klass.find(id)
      when :destroy
        klass.find(id)
      end
 
      instance.id = id
      deserializer_class.new(instance, operation).replicate(amqp_payload[:payload].symbolize_keys)

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
