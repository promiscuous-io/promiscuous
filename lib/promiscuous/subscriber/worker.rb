class Promiscuous::Subscriber::Worker
  include Promiscuous::Common::Worker

  def replicate
    Promiscuous::AMQP.subscribe(subscribe_options) do |metadata, payload|
      begin
        unless self.stop
          # FIXME Investigate: Do we need a mutex around the mongo query ?
          # It wouldn't be surprising that we keep pumping messages while mongo
          # blocks on the socket.
          # If Mongoid uses a poll of connections, we most likely need to
          # serialize. Note that If we do, we just need it during save!
          # TODO Maybe we could offer different levels of consistency, because
          # some of our users may already be resilient to reading out of order
          # writes.

          Promiscuous.info "[receive] #{payload}"
          self.unit_of_work { Promiscuous::Subscriber.process(JSON.parse(payload)) }
          metadata.ack
        end
      rescue Exception => e
        e = Promiscuous::Subscriber::Error.new(e, payload)

        # TODO Discuss with Arjun about having an error queue.
        self.stop = true
        Promiscuous::AMQP.disconnect
        Promiscuous.error "[receive] FATAL #{e}"
        Promiscuous::Config.error_handler.try(:call, e)
      end
    end
  end

  def subscribe_options
    queue_name = "#{Promiscuous::Config.app}.promiscuous"
    bindings = Promiscuous::Subscriber::AMQP.subscribers.keys
    {:queue_name => queue_name, :bindings => bindings}
  end
end
