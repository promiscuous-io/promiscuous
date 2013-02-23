class Promiscuous::Error::InactiveTransaction < Promiscuous::Error::Base
  # Not visible by the end user

  attr_accessor :operation
  def initialize(operation)
    self.operation = operation
  end
end
