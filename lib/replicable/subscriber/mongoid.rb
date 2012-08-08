require 'replicable/subscriber/generic'

class Replicable::Subscriber::Mongoid < Replicable::Subscriber::Generic
  def self.subscribe(options)
    return super if options[:mongoid_loaded]

    klass = options[:class]
    klass = options[:classes].values.first if klass.nil?

    if klass.embedded?
      require 'replicable/subscriber/mongoid/embedded'
      include Replicable::Subscriber::Mongoid::Embedded
    else
      require 'replicable/subscriber/mongoid/root'
      include Replicable::Subscriber::Mongoid::Root
    end

    self.subscribe(options.merge(:mongoid_loaded => true))
  end
end
