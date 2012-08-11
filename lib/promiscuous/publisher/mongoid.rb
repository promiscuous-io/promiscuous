require 'promiscuous/publisher/generic'

class Promiscuous::Publisher::Mongoid < Promiscuous::Publisher::Generic
  def self.publish(options)
    return super if options[:mongoid_loaded]

    if options[:class].embedded?
      require 'promiscuous/publisher/mongoid/embedded'
      include Promiscuous::Publisher::Mongoid::Embedded
    else
      require 'promiscuous/publisher/mongoid/root'
      include Promiscuous::Publisher::Mongoid::Root
    end

    self.publish(options.merge(:mongoid_loaded => true))
  end
end
