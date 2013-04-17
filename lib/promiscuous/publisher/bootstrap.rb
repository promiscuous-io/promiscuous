module Promiscuous::Publisher::Bootstrap
  extend Promiscuous::Autoload
  autoload :Base, :Version, :Data
  KEY = "publishers:#{Promiscuous::Config.app}:bootstrap"

  def self.enable
    Promiscuous::Redis.master.nodes.each { |node| node.set(KEY, 1) }
  end

  def self.disable
    Promiscuous::Redis.master.nodes.each { |node| node.del(KEY, 1) }
  end
end
