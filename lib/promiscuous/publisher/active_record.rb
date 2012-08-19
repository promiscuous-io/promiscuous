class Promiscuous::Publisher::ActiveRecord < Promiscuous::Publisher::Base
  include Promiscuous::Publisher::ClassBind
  include Promiscuous::Publisher::Attributes
  include Promiscuous::Publisher::AMQP
  include Promiscuous::Publisher::Envelope
  include Promiscuous::Publisher::Model
end
