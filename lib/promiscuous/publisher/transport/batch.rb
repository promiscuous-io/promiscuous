class Promiscuous::Publisher::Transport::Batch
  attr_accessor :operations, :payload_attributes, :timestamp, :id, :exchange, :routing

  def initialize(options={})
    self.operations         = []
    self.payload_attributes = options[:payload_attributes] || {}
    self.exchange           = options[:exchange]  || Promiscuous::Config.publisher_exchange
    self.routing            = options[:routing]   || Promiscuous::Config.sync_all_routing
    self.timestamp          = options[:timestamp] || Time.now
  end

  def add(type, instances)
    self.operations << Operation.new(type, instances) if instances.present?
  end

  def clear
    self.operations = []
  end

  def lock
    @lock = Promiscuous::Publisher::Transport::Lock.new(self)
  end

  def publish(raise_error=false)
    Promiscuous::AMQP.ensure_connected

    begin
      if self.operations.present?
        # TODO: Needs to be by instance (only relevant for ActiveRecord)
        self.operations.each do |operation|
          @_payload = self.payload(operation)
          Promiscuous::AMQP.publish(:exchange => self.exchange,
                                    :key => self.routing.to_s,
                                    :payload => @_payload,
                                    :on_confirm => method(:on_rabbitmq_confirm))
        end
      else
        on_rabbitmq_confirm
      end
    rescue Exception => e
      Promiscuous.warn("[publish] Failure publishing to rabbit #{e}\n#{e.backtrace.join("\n")}")
      e = Promiscuous::Error::Publisher.new(e, :payload => @_payload)
      Promiscuous::Config.error_notifier.call(e)

      raise e.inner if raise_error
    end
  end

  def on_rabbitmq_confirm
    @lock.unlock if @lock
  end

  def payload(operation)
    payload = {}
    payload[:operations] = operation.payload
    payload[:app] = Promiscuous::Config.app
    payload[:timestamp] = self.timestamp
    payload[:generation] = Promiscuous::Config.generation
    payload[:host] = Socket.gethostname

    payload.merge!(payload_attributes)

    MultiJson.dump(payload)
  end

  class Operation
    attr_accessor :type, :instances

    def initialize(type, instances)
      self.type      = type
      self.instances = instances
    end

    def payload
      self.instances.map { |instance| instance.promiscuous.payload(:with_attributes => !destroy?).
                                       merge(:operation => type, :version => instance.attributes[Promiscuous::Config.version_field]) }
    end

    def destroy?
      type == 'destroy'
    end
  end
end
