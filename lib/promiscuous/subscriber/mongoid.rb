class Promiscuous::Subscriber::Mongoid < Promiscuous::Subscriber::Base
  autoload :Embedded,   'promiscuous/subscriber/mongoid/embedded'
  autoload :Versioning, 'promiscuous/subscriber/mongoid/versioning'

  include Promiscuous::Subscriber::Class
  include Promiscuous::Subscriber::Attributes
  include Promiscuous::Subscriber::Polymorphic
  include Promiscuous::Subscriber::AMQP

  def self.missing_record_exception
    Mongoid::Errors::DocumentNotFound
  end

  def self.subscribe(options)
    super

    if klass.embedded?
      require 'promiscuous/subscriber/mongoid/embedded_many'
      include Promiscuous::Subscriber::Mongoid::Embedded
    else
      include Promiscuous::Subscriber::Model
      include Promiscuous::Subscriber::Upsert
      include Promiscuous::Subscriber::Mongoid::Versioning
    end
  end
end
