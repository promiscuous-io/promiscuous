class Promiscuous::Publisher::Mongoid < Promiscuous::Publisher::Base
  extend Promiscuous::Autoload
  autoload :Embedded, :EmbeddedMany

  include Promiscuous::Publisher::Class
  include Promiscuous::Publisher::Attributes
  include Promiscuous::Publisher::Polymorphic
  include Promiscuous::Publisher::AMQP

  def self.publish(options)
    super

    if klass.embedded?
      include Promiscuous::Publisher::Mongoid::Embedded
    else
      include Promiscuous::Publisher::Model
      include Promiscuous::Publisher::Model::Generic
    end

    setup_class_binding
  end
end
