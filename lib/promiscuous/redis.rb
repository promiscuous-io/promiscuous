require 'redis'

class Promiscuous::Redis
  class_attribute :connection

  def self.connect
    self.connection = Redis.new(:url => Promiscuous::Config.redis_url)
  end

  def self.ensure_connected
    Promiscuous.ensure_connected

    begin
      connection.ping
    rescue Exception => e
      raise lost_connection_exception(node, :inner => e)
    end
  end

  def self.disconnect
    self.connection.try(:quit)
  end

  def self.lost_connection_exception(node, options={})
    Promiscuous::Error::Connection.new("redis://#{connection.location}", options)
  end
end
