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
            parsed_payload = JSON.parse(payload)
            queue = parsed_payload['__amqp__']
            self.unit_of_work(queue) { Promiscuous::Subscriber.process(parsed_payload) }
            metadata.ack
          end
        rescue Exception => e
          e = Promiscuous::Error::Subscriber.new(e, :payload => payload)

          Promiscuous::Config.error_notifier.try(:call, e)

          if bareback?
            Promiscuous.error "[receive] (bareback, don't care) #{e} #{e.backtrace.join("\n")}"
            metadata.ack
          else
            Promiscuous.error "[receive] #{e} #{e.backtrace.join("\n")}"
            self.stop = true
            Promiscuous::AMQP.disconnect
          end
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
