require 'promiscuous/publisher/base'
require 'promiscuous/publisher/class_bind'
require 'promiscuous/publisher/attributes'
require 'promiscuous/publisher/amqp'
require 'promiscuous/publisher/envelope'
require 'promiscuous/publisher/model'

class Promiscuous::Publisher::ActiveRecord < Promiscuous::Publisher::Base
  include Promiscuous::Publisher::ClassBind
  include Promiscuous::Publisher::Attributes
  include Promiscuous::Publisher::AMQP
  include Promiscuous::Publisher::Envelope
  include Promiscuous::Publisher::Model
end
