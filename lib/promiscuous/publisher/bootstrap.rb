module Promiscuous::Publisher::Bootstrap
  extend Promiscuous::Autoload
  autoload :Base, :Version, :Data
  KEY = 'promiscuous:publisher:bootstrap'

  def self.enable
    Promiscuous::Redis.master.set(KEY, 1)
  end

  def self.disable
    Promiscuous::Redis.master.del(KEY, 1)
  end
end
