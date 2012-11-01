class Promiscuous::Publisher::Mongoid < Promiscuous::Publisher::Base
  autoload :Embedded,      'promiscuous/publisher/mongoid/embedded'
  autoload :DeferEmbedded, 'promiscuous/publisher/mongoid/defer_embedded'
  autoload :Defer,         'promiscuous/publisher/mongoid/defer'
  autoload :EmbeddedMany,  'promiscuous/publisher/mongoid/embedded_many'

  include Promiscuous::Publisher::Class
  include Promiscuous::Publisher::Attributes
  include Promiscuous::Publisher::Polymorphic
  include Promiscuous::Publisher::AMQP

  def self.publish(options)
    super

    if klass.embedded?
      if mongoid3?
        include Promiscuous::Publisher::Mongoid::DeferEmbedded
      else
        include Promiscuous::Publisher::Mongoid::Embedded
      end
    else
      include Promiscuous::Publisher::Model
      include Promiscuous::Publisher::Mongoid::Defer if mongoid3?
    end
  end

  def self.mongoid3?
    Gem.loaded_specs['mongoid'].version >= Gem::Version.new('3.0.0')
  end
end
