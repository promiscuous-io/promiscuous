class Promiscuous::Subscriber::Observer < Promiscuous::Subscriber::Base
  include Promiscuous::Subscriber::Class
  include Promiscuous::Subscriber::Attributes
  include Promiscuous::Subscriber::AMQP
  include Promiscuous::Subscriber::Envelope

  def fetch
    klass.new.tap { |o| o.id = id if o.respond_to?(:id=) }
  end

  def process
    super
    instance.run_callbacks operation
  end

  # XXX destroy callbacks will not set attributes (they are not sent)
  def process_attributes?
    operation != :destroy
  end

  def self.subscribe(options)
    super
    raise "#{klass} must inherit from Promiscuous::Observer" unless klass < Promiscuous::Observer
  end

  def self.subscribe(options)
    super
    use_payload_attribute :id
    use_payload_attribute :operation, :symbolize => true
  end
end
