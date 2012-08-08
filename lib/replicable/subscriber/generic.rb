require 'replicable/subscriber/custom_class'
require 'replicable/subscriber/base'
require 'replicable/subscriber/attributes'
require 'replicable/subscriber/polymorphic'
require 'replicable/subscriber/amqp'
require 'replicable/subscriber/envelope'

class Replicable::Subscriber::Generic < Replicable::Subscriber::Base
  include Replicable::Subscriber::CustomClass
  include Replicable::Subscriber::Attributes
  include Replicable::Subscriber::Polymorphic
  include Replicable::Subscriber::AMQP
  include Replicable::Subscriber::Envelope
end
