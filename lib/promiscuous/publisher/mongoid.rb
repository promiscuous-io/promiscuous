class Promiscuous::Publisher::Mongoid < Promiscuous::Publisher::Base
  autoload :Embedded, 'promiscuous/publisher/mongoid/embedded'
  autoload :Defer,    'promiscuous/publisher/mongoid/defer'

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
      include Promiscuous::Publisher::Mongoid::Defer if mongoid3?
    end
  end

  def self.mongoid3?
    Gem.loaded_specs['mongoid'].version >= Gem::Version.new('3.0.0')
  end
end
