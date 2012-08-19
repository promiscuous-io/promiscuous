class Promiscuous::Subscriber::Mongoid < Promiscuous::Subscriber::Base
  autoload :Embedded, 'promiscuous/subscriber/mongoid/embedded'

  include Promiscuous::Subscriber::CustomClass
  include Promiscuous::Subscriber::Attributes
  include Promiscuous::Subscriber::Polymorphic
  include Promiscuous::Subscriber::AMQP
  include Promiscuous::Subscriber::Envelope

  def self.missing_record_exception
    Mongoid::Errors::DocumentNotFound
  end

  def self.subscribe(options)
    super

    if klass.embedded?
      include Promiscuous::Subscriber::Mongoid::Embedded
    else
      include Promiscuous::Subscriber::Model
      include Promiscuous::Subscriber::Upsert
    end
  end
end
