module Promiscuous::Publisher::Operation
  extend Promiscuous::Autoload
  autoload :Base, :Transaction, :Atomic, :NonPersistent, :ProxyForQuery, :Ephemeral, :Recovery
end
