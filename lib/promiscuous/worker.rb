module Promiscuous
  module Worker
    def self.replicate
      stop = false

      unless ENV['TEST_ENV']
        %w(SIGTERM SIGINT).each do |signal|
          Signal.trap(signal) do
            stop = true
            Promiscuous.info "exiting gracefully"
          end
        end
      end

      Promiscuous::AMQP.subscribe(subscribe_options) do |metadata, payload|
        begin
          if stop
            EM.stop
          else
            Promiscuous.info "[receive] #{payload}"
            Promiscuous::Subscriber.process(JSON.parse(payload))
            metadata.ack
          end
        rescue Exception => e
          e = Promiscuous::Subscriber::Error.new(e, payload)

          stop = true
          Promiscuous::AMQP.disconnect
          Promiscuous.error "[receive] FATAL #{e}"
          Promiscuous::Config.error_handler.call(e) if Promiscuous::Config.error_handler
        end
      end
    end

    def self.subscribe_options
      queue_name = "#{Promiscuous::Config.app}.promiscuous"
      bindings = Promiscuous::Subscriber.subscribers.keys
      {:queue_name => queue_name, :bindings => bindings}
    end
  end
end
