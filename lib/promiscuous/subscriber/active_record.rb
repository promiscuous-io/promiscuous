require 'promiscuous/subscriber/base'
require 'promiscuous/subscriber/custom_class'
require 'promiscuous/subscriber/attributes'
require 'promiscuous/subscriber/amqp'
require 'promiscuous/subscriber/model'

class Promiscuous::Subscriber::ActiveRecord < Promiscuous::Subscriber::Base
  include Promiscuous::Subscriber::CustomClass
  include Promiscuous::Subscriber::Attributes
  include Promiscuous::Subscriber::AMQP
  include Promiscuous::Subscriber::Model

  def self.subscribe(options)
    return super if options[:active_record_loaded]

    if options[:upsert]
      require 'promiscuous/subscriber/active_record/upsert'
      include Promiscuous::Subscriber::ActiveRecord::Upsert
    end

    self.subscribe(options.merge(:active_record_loaded => true))
  end
end
