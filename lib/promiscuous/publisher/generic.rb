require 'promiscuous/publisher/class_bind'
require 'promiscuous/publisher/base'
require 'promiscuous/publisher/attributes'
require 'promiscuous/publisher/polymorphic'
require 'promiscuous/publisher/amqp'
require 'promiscuous/publisher/envelope'

class Promiscuous::Publisher::Generic < Promiscuous::Publisher::Base
  include Promiscuous::Publisher::ClassBind
  include Promiscuous::Publisher::Attributes
  include Promiscuous::Publisher::Polymorphic
  include Promiscuous::Publisher::AMQP
  include Promiscuous::Publisher::Envelope
end
