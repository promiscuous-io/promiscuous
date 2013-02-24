module Promiscuous::Error
  extend Promiscuous::Autoload
  autoload :Base, :Connection, :Publisher, :Subscriber, :Recover, :Dependency,
           :MissingTransaction, :InactiveTransaction, :ClosedTransaction,
           :IdempotentViolation
end
