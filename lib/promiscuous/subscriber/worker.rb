class Promiscuous::Subscriber::Worker
  include Promiscuous::Common::Worker

  def replicate
    Promiscuous::AMQP.open_queue(queue_bindings) do |queue|
      queue.subscribe :ack => true do |metadata, payload|
        # Note: This code always runs on the root Fiber,
        # so ordering is always preserved
        begin
          unless self.stop
            Promiscuous.info "[receive] #{payload}"
            self.unit_of_work { Promiscuous::Subscriber.process(JSON.parse(payload)) }
            metadata.ack
          end
        rescue Exception => e
          e = Promiscuous::Subscriber::Error.new(e, payload)

          if bareback?
            metadata.ack
          else
            self.stop = true
            Promiscuous::AMQP.disconnect
          end
          Promiscuous.error "[receive] FATAL #{"skipping " if bareback?}#{e} #{e.backtrace.join("\n")}"
          Promiscuous::Config.error_handler.try(:call, e)
        end
      end
    end
  end

  def queue_bindings
    queue_name = "#{Promiscuous::Config.app}.promiscuous"
    exchange_name = Promiscuous::AMQP::EXCHANGE

    if options[:personality]
      queue_name    += ".#{options[:personality]}"
      exchange_name += ".#{options[:personality]}"
    end

    bindings = Promiscuous::Subscriber::AMQP.subscribers.keys
    {:exchange_name => exchange_name, :queue_name => queue_name, :bindings => bindings}
  end
end
