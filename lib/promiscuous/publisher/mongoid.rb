class Promiscuous::Publisher::Mongoid < Promiscuous::Publisher::Base
  extend Promiscuous::Autoload
  autoload :Embedded, :EmbeddedMany

  include Promiscuous::Publisher::Class
  include Promiscuous::Publisher::Attributes
  include Promiscuous::Publisher::Polymorphic
  include Promiscuous::Publisher::AMQP

  def self.publish(options)
    check_mongoid_version
    super

    if klass.embedded?
      include Promiscuous::Publisher::Mongoid::Embedded
    else
      include Promiscuous::Publisher::Model
      include Promiscuous::Publisher::Model::Mongoid
    end

    setup_class_binding
  end

  def self.check_mongoid_version
    unless Gem.loaded_specs['mongoid'].version >= Gem::Version.new('3.0.19')
      raise "mongoid > 3.0.19 please"
    end

    unless Gem.loaded_specs['moped'].version >= Gem::Version.new('1.3.2')
      raise "moped > 1.3.2 please"
    end
  end
end
