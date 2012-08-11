require 'promiscuous/subscriber/custom_class'
require 'promiscuous/subscriber/base'
require 'promiscuous/subscriber/attributes'
require 'promiscuous/subscriber/polymorphic'
require 'promiscuous/subscriber/amqp'
require 'promiscuous/subscriber/envelope'

class Promiscuous::Subscriber::Generic < Promiscuous::Subscriber::Base
  include Promiscuous::Subscriber::CustomClass
  include Promiscuous::Subscriber::Attributes
  include Promiscuous::Subscriber::Polymorphic
  include Promiscuous::Subscriber::AMQP
  include Promiscuous::Subscriber::Envelope
end
