module Promiscuous::Error
  extend Promiscuous::Autoload
  autoload :Base, :Connection, :Publisher, :Subscriber, :Recovery,
           :Dependency, :MissingContext, :AlreadyProcessed,
           :LockUnavailable, :LostLock, :Retry
end
