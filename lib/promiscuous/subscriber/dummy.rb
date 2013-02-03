class Promiscuous::Subscriber::Dummy < Promiscuous::Subscriber::Base
  include Promiscuous::Subscriber::Class
  include Promiscuous::Subscriber::Attributes
  include Promiscuous::Subscriber::AMQP
  include Promiscuous::Subscriber::Envelope
  include Promiscuous::Subscriber::Model

  class DummyInstance
    attr_accessor :id
  end

  def klass
    DummyInstance
  end

  def operation
    :dummy
  end
end
