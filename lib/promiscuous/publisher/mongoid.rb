class Promiscuous::Publisher::Mongoid < Promiscuous::Publisher::Base
  autoload :Embedded, 'promiscuous/publisher/mongoid/embedded'

  include Promiscuous::Publisher::ClassBind
  include Promiscuous::Publisher::Attributes
  include Promiscuous::Publisher::Polymorphic
  include Promiscuous::Publisher::AMQP
  include Promiscuous::Publisher::Envelope

  def self.publish(options)
    super

    if klass.embedded?
      include Promiscuous::Publisher::Mongoid::Embedded
    else
      include Promiscuous::Publisher::Model
    end
  end
end
