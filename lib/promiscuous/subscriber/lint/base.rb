class Promiscuous::Subscriber::Lint::Base
  include Promiscuous::Common::Lint::Base

  class_attribute :check_publisher
  self.check_publisher = Promiscuous::Publisher::Mock.descendants.present?

  use_option(:subscriber)
end
