require 'promiscuous/subscriber/base'
require 'promiscuous/subscriber/custom_class'
require 'promiscuous/subscriber/attributes'
require 'promiscuous/subscriber/polymorphic'
require 'promiscuous/subscriber/amqp'
require 'promiscuous/subscriber/envelope'

class Promiscuous::Subscriber::Mongoid < Promiscuous::Subscriber::Base
  include Promiscuous::Subscriber::CustomClass
  include Promiscuous::Subscriber::Attributes
  include Promiscuous::Subscriber::Polymorphic
  include Promiscuous::Subscriber::AMQP
  include Promiscuous::Subscriber::Envelope

  def self.subscribe(options)
    return super if options[:mongoid_loaded]

    klass = options[:class]
    klass = options[:classes].values.first if klass.nil?

    if klass.embedded?
      require 'promiscuous/subscriber/mongoid/embedded'
      include Promiscuous::Subscriber::Mongoid::Embedded
    else
      require 'promiscuous/subscriber/model'
      include Promiscuous::Subscriber::Model

      if options[:upsert]
        require 'promiscuous/subscriber/mongoid/upsert'
        include Promiscuous::Subscriber::Mongoid::Upsert
      end
    end

    self.subscribe(options.merge(:mongoid_loaded => true))
  end
end
