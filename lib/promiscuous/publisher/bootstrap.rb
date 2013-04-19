module Promiscuous::Publisher::Bootstrap
  extend Promiscuous::Autoload
  autoload :Base, :Version, :Data

  def self.enable
    Promiscuous::Redis.master.nodes.each { |node| node.set(bootstrap_mode_key, 1) }
  end

  def self.disable
    Promiscuous::Redis.master.nodes.each { |node| node.del(bootstrap_mode_key) }
  end

  def self.bootstrap_mode_key
    # XXX You must change the LUA script in promiscuous/publisher/operation/base.rb
    # if you change this value
    Promiscuous::Key.new(:pub).join('bootstrap')
  end
end
