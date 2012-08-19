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

  def self.missing_record_exception
    Mongoid::Errors::DocumentNotFound
  end

  def self.subscribe(options)
    super

    if klass.embedded?
      require 'promiscuous/subscriber/mongoid/embedded'
      include Promiscuous::Subscriber::Mongoid::Embedded
    else
      require 'promiscuous/subscriber/model'
      include Promiscuous::Subscriber::Model

      require 'promiscuous/subscriber/upsert'
      include Promiscuous::Subscriber::Upsert
    end
  end
end
