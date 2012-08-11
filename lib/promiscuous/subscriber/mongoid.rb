require 'promiscuous/subscriber/generic'

class Promiscuous::Subscriber::Mongoid < Promiscuous::Subscriber::Generic
  def self.subscribe(options)
    return super if options[:mongoid_loaded]

    klass = options[:class]
    klass = options[:classes].values.first if klass.nil?

    if klass.embedded?
      require 'promiscuous/subscriber/mongoid/embedded'
      include Promiscuous::Subscriber::Mongoid::Embedded
    else
      require 'promiscuous/subscriber/mongoid/root'
      include Promiscuous::Subscriber::Mongoid::Root

      if options[:upsert]
        require 'promiscuous/subscriber/mongoid/upsert'
        include Promiscuous::Subscriber::Mongoid::Upsert
      end
    end

    self.subscribe(options.merge(:mongoid_loaded => true))
  end
end
