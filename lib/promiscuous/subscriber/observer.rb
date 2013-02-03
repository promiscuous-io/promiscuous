class Promiscuous::Subscriber::Observer < Promiscuous::Subscriber::Base
  include Promiscuous::Subscriber::Class
  include Promiscuous::Subscriber::Attributes
  include Promiscuous::Subscriber::Polymorphic
  include Promiscuous::Subscriber::AMQP
  include Promiscuous::Subscriber::Envelope
  include Promiscuous::Subscriber::Model

  def fetch
    klass.new.tap { |o| o.id = id if o.respond_to?(:id=) }
  end

  def commit
    with_dependencies do
      instance.run_callbacks operation unless operation == :dummy
    end
  end

  def self.subscribe(options)
    super
    raise "#{klass} must inherit from Promiscuous::Observer" unless klass < Promiscuous::Observer

    use_payload_attribute :id
    use_payload_attribute :operation, :symbolize => true
  end
end
