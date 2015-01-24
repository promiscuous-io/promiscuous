module RedisLockHelper
  def redis_lock_count
    Promiscuous::Redis.connection.zcount(Redis::Lock.key_group_key(Promiscuous::Publisher::Operation::Base.lock_options), '-inf', '+inf')
  end
end
