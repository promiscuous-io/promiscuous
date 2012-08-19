require 'promiscuous/publisher/base'
require 'promiscuous/publisher/class_bind'
require 'promiscuous/publisher/attributes'
require 'promiscuous/publisher/polymorphic'
require 'promiscuous/publisher/amqp'
require 'promiscuous/publisher/envelope'

class Promiscuous::Publisher::Mongoid < Promiscuous::Publisher::Base
  include Promiscuous::Publisher::ClassBind
  include Promiscuous::Publisher::Attributes
  include Promiscuous::Publisher::Polymorphic
  include Promiscuous::Publisher::AMQP
  include Promiscuous::Publisher::Envelope

  def self.publish(options)
    super

    if klass.embedded?
      require 'promiscuous/publisher/mongoid/embedded'
      include Promiscuous::Publisher::Mongoid::Embedded
    else
      require 'promiscuous/publisher/model'
      include Promiscuous::Publisher::Model
    end
  end
end
