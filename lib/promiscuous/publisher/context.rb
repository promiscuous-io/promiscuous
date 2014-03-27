module Promiscuous::Publisher::Context
  extend Promiscuous::Autoload
  autoload :Base, :Transaction

  def self.current
    Base.current
  end
end
