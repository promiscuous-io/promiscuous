module Replicable
  module Subscriber
    module Worker
      mattr_accessor :klass_map, :bindings

      def self.run
        self.klass_map = {}
        self.bindings = []

        Replicable::Subscriber.subscriptions.each { |klass| prepare_bindings(klass, klass.replicate_options) }
        queue_name = "#{Replicable::AMQP.app}.replicable"

        Replicable::AMQP.subscribe(:queue_name => queue_name, :bindings => bindings.flatten) do |metadata, payload|
          Replicable::AMQP.logger.info "[receive] #{payload}"
          self.process(JSON.parse(payload).symbolize_keys)
          metadata.ack
        end
      end

      def self.prepare_bindings(klass, options)
        from       = options[:from]
        fields     = options[:fields]
        class_name = options[:class_name]

        self.bindings += fields.map { |field| "#{from}.#.#{class_name}.#.update.$fields$.#.#{field}.#" }
        self.bindings += [:create, :destroy].map { |op| "#{from}.#.#{class_name}.#.#{op}.$fields$.#" }

        # TODO raise exception if already there
        self.klass_map[class_name] = klass
      end

      def self.process(payload)
        payload[:classes].each do |class_name|
          klass = self.klass_map[class_name]
          raise "Unknown class: '#{payload[:class]}'" if klass.nil?
          self.process_for(klass, payload)
        end
      end

      def self.process_for(klass, payload)
        id     = payload[:id]
        fields = payload[:fields].symbolize_keys.select { |field| field.in?(klass.replicate_options[:fields]) }

        case payload[:operation].to_sym
        when :create
          klass.new(fields).tap { |instance| instance.id = id }.save!
        when :update
          klass.find(id).update_attributes!(fields)
        when :destroy
          klass.find(id).destroy!
        end
      end
    end
  end
end
