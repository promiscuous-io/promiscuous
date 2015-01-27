class Promiscuous::Error::PublishUnacknowledged < Promiscuous::Error::Base
  attr_accessor :payload

  def initialize(payload, options={})
    self.payload  = options[:payload]
  end

  def message
    "Unacknowledged publishing of #{payload}"
  end

  alias to_s message
end
