module Promiscuous::Publisher::Context
  extend Promiscuous::Autoload
  autoload :Base, :Transaction, :Middleware

  def self.current
    Base.current
  end
end
