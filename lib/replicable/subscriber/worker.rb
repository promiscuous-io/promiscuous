module Replicable
  module Subscriber
    module Worker
      def self.run
        Replicable::Subscriber.subscriptions.each do |klass|
          subscribe(klass, klass.replicate_options)
        end
      end

      def self.subscribe(klass, options)
        from       = options[:from]
        fields     = options[:fields]
        class_name = options[:class_name]

        queue_name = "#{Replicable::AMQP.app}.replicable"
        bindings   = fields.map { |field| "#{from}.#.#{class_name}.#.update.$fields$.#.#{field}.#" }
        bindings   += [:create, :destroy].map { |op| "#{from}.#.#{class_name}.#.#{op}.$fields$.#" }

        Replicable::AMQP.subscribe(:queue_name => queue_name, :bindings => bindings) do |metadata, payload|
          self.process(klass, JSON.parse(payload).symbolize_keys)
          metadata.ack
        end
      end

      def self.process(klass, payload)
        id = payload[:id]
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
