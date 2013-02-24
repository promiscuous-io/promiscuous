class Promiscuous::Error::InactiveTransaction < Promiscuous::Error::Base
  # Not visible by the end user

  attr_accessor :operation, :transaction
  def initialize(operation)
    self.operation = operation
    self.transaction = Promiscuous::Publisher::Transaction.current
  end
end
