module Promiscuous::Publisher::Bootstrap
  extend Promiscuous::Autoload
  autoload :Connection, :Version, :Data, :Mode

  def self.setup
    Mode.enable
    Version.bootstrap
    Data.setup
  end

  def self.start
    raise "Setup must be run before starting to bootstrap" unless Mode.enabled?
    Data.start
  end

  def self.finalize
    raise "Setup must be run before disabling" unless Mode.enabled?
    Mode.disable
  end
end
