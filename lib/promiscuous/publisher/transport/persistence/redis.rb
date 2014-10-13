class Promiscuous::Publisher::Transport::Persistence::Redis
  def save(batch)
    batch.id = SecureRandom.uuid

    redis.multi do
      redis.zadd(key, Time.now.utc.to_i, batch.id)
      redis.set(key(batch.id), batch.dump)
    end
  end

  def expired
    redis.zrangebyscore(key, 0, Promiscuous::Config.recovery_timeout.seconds.ago.utc.to_i).map do |batch_id|
      [batch_id, redis.get(key(batch_id))]
    end
  end

  def delete(batch)
    redis.multi do
      redis.zrem(key, batch.id)
      redis.del(key(batch.id))
    end
  end

  private

  def redis
    Promiscuous.ensure_connected
    Promiscuous::Redis.connection
  end

  def key(id=nil)
    Promiscuous::Key.new(:pub).join('transport').join(id)
  end
end
