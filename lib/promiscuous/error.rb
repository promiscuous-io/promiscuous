module Promiscuous::Error
  extend Promiscuous::Autoload
  autoload :Base, :Connection, :Publisher, :Subscriber,
           :LockUnavailable, :PublishUnacknowledged
end
