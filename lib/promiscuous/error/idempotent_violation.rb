class Promiscuous::Error::IdempotentViolation < Promiscuous::Error::Base
  attr_accessor :transaction

  def initialize(options={})
    self.transaction = Promiscuous::Publisher::Transaction.current
  end

  def message
    msg = "Promiscuous detected an idempotent issue with the #{transaction.name} transaction."

    if transaction.write_attempts.present?
      msg += "\nThe following write never happened during the retry of the transaction:\n\n"
      msg += transaction.write_attempts.map { |operation| "  #{Promiscuous::Error::Dependency.explain_operation(operation)}" }.join("\n") + "\n\n"
    end
  end

  def to_s
    message
  end
end
