class Promiscuous::Subscriber::Worker::Bootstrap
  def initialize
    class << self
      include Promiscuous::AMQP::Subscriber
      alias_method :start, :connect
      alias_method :stop, :disconnect
    end

    raise "Bootstrap mode?" unless Promiscuous::Config.bootstrap
  end

  def connect
    options = {}
    # We need to subscribe to everything to keep up with the version tracking
    options[:bindings] = ['*']
    subscribe(options, &method(:on_message))
  end

  def on_message_version(metadata, parsed_payload)
    keys = parsed_payload['keys']
    keys.map { |k| Promiscuous::Dependency.parse(k) }.group_by(&:redis_node).each do |node, deps|
      node.pipelined do
        deps.each do |dep|
          node.set(dep.key(:sub).to_s, dep.version)
        end
      end
    end
    metadata.ack
  end

  def on_message_sync(metadata, payload)
    # TODO Don't parse twice
    Promiscuous::Subscriber::Worker::Message.new(payload, :metadata => metadata).process
  end

  def on_message(metadata, payload)
    parsed_payload = MultiJson.load(payload)
    case parsed_payload['operation']
    when 'versions' then on_message_version(metadata, parsed_payload)
    when 'sync'     then on_message_sync(metadata, payload)
    else raise "Unkown message received: #{payload}"
    end

  rescue Exception => e
    Promiscuous.warn "[bootstrap] cannot process message: #{e} #{e.backtrace.join("\n")}"
    Promiscuous::Config.error_notifier.try(:call, e)
  end
end
