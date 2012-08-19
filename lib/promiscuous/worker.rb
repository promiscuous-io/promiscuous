module Promiscuous
  module Worker
    mattr_accessor :stop

    def self.replicate
      self.stop = false
      self.trap_signals unless ENV['TEST_ENV']

      Promiscuous::AMQP.subscribe(subscribe_options) do |metadata, payload|
        begin
          unless self.stop
            Promiscuous.info "[receive] #{payload}"
            self.mongoid_wrapper { Promiscuous::Subscriber.process(JSON.parse(payload)) }
            metadata.ack
          end
        rescue Exception => e
          e = Promiscuous::Subscriber::Error.new(e, payload)

          self.stop = true
          Promiscuous::AMQP.disconnect
          Promiscuous.error "[receive] FATAL #{e}"
          Promiscuous::Config.error_handler.call(e) if Promiscuous::Config.error_handler
        end
      end
    end

    def self.mongoid_wrapper
      if defined?(Mongoid)
        Mongoid.unit_of_work { yield }
      else
        yield
      end
    end

    def self.trap_signals
      %w(SIGTERM SIGINT).each do |signal|
        Signal.trap(signal) do
          self.stop = true
          EM.stop
          Promiscuous.info "exiting gracefully"
        end
      end
    end

    def self.subscribe_options
      queue_name = "#{Promiscuous::Config.app}.promiscuous"
      bindings = Promiscuous::Subscriber::AMQP.subscribers.keys
      {:queue_name => queue_name, :bindings => bindings}
    end
  end
end
