require 'replicable/publisher/generic'

class Replicable::Publisher::Mongoid < Replicable::Publisher::Generic
  def self.publish(options)
    return super if options[:mongoid_loaded]

    if options[:class].embedded?
      require 'replicable/publisher/mongoid/embedded'
      include Replicable::Publisher::Mongoid::Embedded
    else
      require 'replicable/publisher/mongoid/root'
      include Replicable::Publisher::Mongoid::Root
    end

    self.publish(options.merge(:mongoid_loaded => true))
  end
end
