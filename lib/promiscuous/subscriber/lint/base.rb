class Promiscuous::Subscriber::Lint::Base
  include Promiscuous::Common::Lint::Base

  class_attribute :publishers
  def self.reload_publishers
    self.publishers = Promiscuous::Publisher::Mock.descendants
  end

  def check_publisher
    self.class.publishers.present?
  end

  use_option(:subscriber)
end
