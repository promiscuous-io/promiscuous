module Promiscuous::Publisher::Bootstrap::Mode
  def self.enable
    Promiscuous::Redis.master.nodes.each { |node| node.set(key, 1) }
  end

  def self.disable
    Promiscuous::Redis.master.nodes.each { |node| node.del(key) }
  end

  def self.key
    # XXX You must change the LUA script in promiscuous/publisher/operation/base.rb
    # if you change this value
    Promiscuous::Key.new(:pub).join('bootstrap')
  end
end
