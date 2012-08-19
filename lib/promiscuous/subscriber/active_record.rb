class Promiscuous::Subscriber::ActiveRecord < Promiscuous::Subscriber::Base
  include Promiscuous::Subscriber::CustomClass
  include Promiscuous::Subscriber::Attributes
  include Promiscuous::Subscriber::AMQP
  include Promiscuous::Subscriber::Model
  include Promiscuous::Subscriber::Upsert

  def self.missing_record_exception
    ActiveRecord::RecordNotFound
  end
end
