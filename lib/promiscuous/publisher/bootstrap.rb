module Promiscuous::Publisher::Bootstrap
  extend Promiscuous::Autoload
  autoload :Connection, :Version, :Data, :Mode

  def self.setup
    Mode.enable
    Version.bootstrap
    Data.setup
  end
end
