class Promiscuous::Publisher::Ephemeral < Promiscuous::Publisher::Base
  include Promiscuous::Publisher::Class
  include Promiscuous::Publisher::Attributes
  include Promiscuous::Publisher::AMQP

  def payload
    super.merge(:operation => :create)
  end
end
