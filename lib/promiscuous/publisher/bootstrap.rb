module Promiscuous::Publisher::Bootstrap
  extend Promiscuous::Autoload
  autoload :Connection, :Version, :Data, :Mode, :Status

  def self.setup
    Mode.enable
    Version.bootstrap
    Data.setup
  end

  def self.run
    raise "Setup must be run before starting to bootstrap" unless Mode.enabled?
    Data.run
  end

  def self.finalize
    raise "Setup must be run before disabling" unless Mode.enabled?
    Mode.disable
  end

  def self.status
    Status.monitor
  end
end
