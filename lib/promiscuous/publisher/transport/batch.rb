class Promiscuous::Publisher::Transport::Batch
  attr_accessor :operations, :payload_attributes, :timestamp, :id, :exchange, :routing

  SERIALIZER = MultiJson

  def self.load(id, dump)
    data = SERIALIZER.load(dump)

    batch = self.new
    batch.id = id
    batch.timestamp = data['timestamp']
    batch.payload_attributes = data['payload_attributes']
    batch.exchange = data['exchange']
    batch.routing = data['routing']

    data['operations'].each { |op_data| batch.operations << Operation.load(op_data) }

    batch
  end

  def initialize(options={})
    self.operations         = []
    self.payload_attributes = {}
    self.exchange           = options[:exchange] || Promiscuous::Config.publisher_exchange
    self.routing            = options[:routing]  || Promiscuous::Config.sync_all_routing
    self.timestamp          = Time.now
  end

  def add(type, instances)
    self.operations << Operation.new(type, instances) if instances.present?
  end

  def clear
    self.operations = []
  end

  def prepare
    Promiscuous::Publisher::Transport.persistence.save(self)
  end

  def publish(raise_error=false)
    Promiscuous::AMQP.ensure_connected

    begin
      if self.operations.present?
        Promiscuous::AMQP.publish(:exchange => self.exchange,
                                  :key => self.routing,
                                  :payload => self.payload,
                                  :on_confirm => method(:on_rabbitmq_confirm))
      else
        on_rabbitmq_confirm
      end
    rescue Exception => e
      Promiscuous.warn("[publish] Failure publishing to rabbit #{e}\n#{e.backtrace.join("\n")}")
      e = Promiscuous::Error::Publisher.new(e, :payload => self.payload)
      Promiscuous::Config.error_notifier.call(e)

      raise e.inner if raise_error
    end
  end

  def on_rabbitmq_confirm
    Promiscuous::Publisher::Transport.persistence.delete(self) if self.id
  end

  def payload
    payload = {}
    payload[:operations] = self.operations.map(&:payload).flatten
    payload[:app] = Promiscuous::Config.app
    payload[:timestamp] = self.timestamp
    payload[:generation] = Promiscuous::Config.generation
    payload[:host] = Socket.gethostname

    # Backwards compatibility
    payload[:dependencies] = {}
    payload[:dependencies][:write] = operations.map(&:versions).flatten.map { |v| "xxx:#{v}" }

    payload.merge!(payload_attributes)

    MultiJson.dump(payload)
  end

  def dump
    SERIALIZER.dump(
    {
      :operations => self.operations.map(&:dump),
      :payload_attributes => self.payload_attributes,
      :timestamp => self.timestamp,
      :exchange => self.exchange,
      :routing => self.routing
    })
  end

  class Operation
    attr_accessor :type, :instances

    def self.load(dump)
      instances = dump['instances'].map do |attributes|
        if dump['type'] == 'destroy'
          instance_class(attributes).new.tap { |instance| instance.id = attributes['id'] }
        else
          find_instance(attributes)
        end
      end.compact
      self.new(dump['type'], instances)
    end

    def initialize(type, instances, params={})
      self.type      = type
      self.instances = instances
    end

    def payload
      self.instances.map { |instance| instance.promiscuous.payload(:with_attributes => !destroy?).
                                       merge(:operation => type, :version => instance.attributes[Promiscuous::Config.version_field]) }
    end

    def versions
      instances.map { |instance| instance.attributes[Promiscuous::Config.version_field.to_s] }.flatten
    end

    def dump
      instances_metadata = instances.map do |instance|
        {
          :id    => instance.id,
          :class => instance.class.to_s
        }
      end
      {
        :type => type,
        :instances => instances_metadata
      }
    end

    def destroy?
      type == 'destroy'
    end

    private

    def self.find_instance(attributes)
      instance_class(attributes).where(:id => attributes['id']).first
    end

    def self.instance_class(attributes)
      attributes['class'].constantize
    end
  end
end
