class Promiscuous::Subscriber::Worker
  include Promiscuous::Common::Worker

  def resume
    if @queue
      # XXX TODO we should not access to the channel like this.
      # The abstraction is leaking.
      # Actually, we actually want one channel per worker.

      # The following tells rabbitmq to resend the unacked messages
      Promiscuous::AMQP::RubyAMQP.channel.recover
    else
      Promiscuous::AMQP.open_queue(queue_bindings) do |queue|
        @queue = queue
        @queue.subscribe({:ack => true}, &method(:process_payload))
      end
    end

    super
  end

  def process_payload(metadata, payload)
    return if self.stopped?

    # Note: This code always runs on the root Fiber,
    # so ordering is always preserved

    Promiscuous.debug "[receive] #{payload}".light_cyan
    parsed_payload = JSON.parse(payload)
    queue = parsed_payload['__amqp__']

    self.unit_of_work(queue) { Promiscuous::Subscriber.process(parsed_payload) }

    metadata.ack
    made_progress
  rescue Exception => e
    e = Promiscuous::Error::Subscriber.new(e, :payload => payload)

    if bareback?
      Promiscuous.error "[receive] (bareback, don't care) #{e} #{e.backtrace.join("\n")}"
      metadata.ack
    else
      retry_msg = stop_for_a_while(e)
      Promiscuous.warn "[receive] (#{retry_msg}) #{e} #{e.backtrace.join("\n")}"
    end

    Promiscuous::Config.error_notifier.try(:call, e)
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
