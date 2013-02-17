module Promiscuous::Error
  extend Promiscuous::Autoload
  autoload :Connection, :Publisher, :Subscriber, :Recover, :Dependency,
           :MissingTransaction, :InactiveTransaction
end
