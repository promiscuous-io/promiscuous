class Promiscuous::Publisher::ActiveRecord < Promiscuous::Publisher::Base
  include Promiscuous::Publisher::Class
  include Promiscuous::Publisher::Attributes
  include Promiscuous::Publisher::AMQP
  include Promiscuous::Publisher::Model
  include Promiscuous::Publisher::Model::ActiveRecord
end
