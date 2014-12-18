require 'robust-redis-lock'

class Promiscuous::Publisher::Transport
  extend Promiscuous::Autoload
  autoload :Batch, :Worker, :Lock

  def self.expired
    Redis::Lock.expired(Promiscuous::Publisher::Transport::Lock::lock_options.merge(:redis => redis))
  end

  def self.redis
    Promiscuous.ensure_connected
    Promiscuous::Redis.connection
  end
end
