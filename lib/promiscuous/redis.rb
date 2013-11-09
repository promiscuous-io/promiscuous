require 'redis'
require 'redis/distributed'
require 'digest/sha1'

module Promiscuous::Redis
  def self.connect
    disconnect
    @master = new_connection
  end

  def self.master
    ensure_connected unless @master
    @master
  end

  def self.slave
    ensure_connected unless @slave
    @slave
  end

  def self.ensure_slave
    # ensure_slave is called on the first publisher declaration.
    if Promiscuous::Config.redis_slave_url
      self.slave = new_connection(Promiscuous::Config.redis_slave_url)
    end
  end

  def self.disconnect
    @master.quit if @master
    @slave.quit  if @slave
    @master = nil
    @slave  = nil
  end

  def self.new_connection(url=nil)
    url ||= Promiscuous::Config.redis_urls
    redis = ::Redis::Distributed.new(url, :tcp_keepalive => 60)

    redis.info.each do |info|
      version = info['redis_version']
      unless Gem::Version.new(version) >= Gem::Version.new('2.6.0')
        raise "You are using Redis #{version}. Please use Redis 2.6.0 or later."
      end
    end

    redis
  end

  def self.new_blocking_connection
    # This removes the read/select loop in redis, it's weird and unecessary when
    # blocking on the connection.
    new_connection.tap do |redis|
      redis.nodes.each do |node|
        node.client.connection.instance_eval do
          @sock.instance_eval do
            def _read_from_socket(nbytes)
              readpartial(nbytes)
            end
          end
        end
      end
    end
  end

  def self.ensure_connected
    Promiscuous.ensure_connected

    @master.nodes.each do |node|
      begin
        node.ping
      rescue Exception => e
        raise lost_connection_exception(node, :inner => e)
      end
    end
  end

  def self.lost_connection_exception(node, options={})
    Promiscuous::Error::Connection.new("redis://#{node.location}", options)
  end

  class Script
    def initialize(script)
      @script = script
      @sha = Digest::SHA1.hexdigest(@script)
    end

    def eval(redis, options={})
      redis.evalsha(@sha, options)
    rescue ::Redis::CommandError => e
      if e.message =~ /^NOSCRIPT/
        redis.script(:load, @script)
        retry
      end
      raise e
    end

    def to_s
      @script
    end
  end

  class Mutex
    attr_reader :token

    def initialize(key, options={})
      # TODO remove old code with orig_key
      @orig_key = key.to_s
      @key      = "#{key}:lock"
      @timeout  = options[:timeout].to_i
      @sleep    = options[:sleep].to_f
      @expire   = options[:expire].to_i
      @lock_set = options[:lock_set]
      @node     = options[:node]
      raise "Which node?" unless @node
    end

    def key
      @orig_key
    end

    def node
      @node
    end

    def lock
      result = false
      start_at = Time.now
      while Time.now - start_at < @timeout
        break if result = try_lock
        sleep @sleep
      end
      result
    end

    def try_lock
      raise "You are trying to lock an already locked mutex" if @token

      now = Time.now.to_i

      # This script loading is not thread safe (touching a class variable), but
      # that's okay, because the race is harmless.
      @@lock_script ||= Promiscuous::Redis::Script.new <<-SCRIPT
        local key = KEYS[1]
        local token_key = KEYS[2]
        local lock_set = KEYS[3]
        local now = tonumber(ARGV[1])
        local expires_at = tonumber(ARGV[2])
        local orig_key = ARGV[3]

        local prev_expires_at = tonumber(redis.call('hget', key, 'expires_at'))
        if prev_expires_at and prev_expires_at > now then
          return {false, nil}
        end

        local next_token = redis.call('incr', 'promiscuous:next_token')

        redis.call('hmset', key, 'expires_at', expires_at, 'token', next_token)

        if lock_set then
          redis.call('zadd', lock_set, now, orig_key)
        end

        if prev_expires_at then
          return {'recovered', next_token}
        else
          return {true, next_token}
        end
      SCRIPT
      result, @token = @@lock_script.eval(@node, :keys => [@key, 'promiscuous:next_token', @lock_set].compact,
                                                 :argv => [now, now + @expire, @orig_key])
      result == 'recovered' ? :recovered : !!result
    end

    def extend
      now  = Time.now.to_i
      @@extend_script ||= Promiscuous::Redis::Script.new <<-SCRIPT
        local key = KEYS[1]
        local expires_at = tonumber(ARGV[1])
        local token = ARGV[2]

        if redis.call('hget', key, 'token') == token then
          redis.call('hset', key, 'expires_at', expires_at)
          return true
        else
          return false
        end
      SCRIPT
      !!@@extend_script.eval(@node, :keys => [@key].compact, :argv => [now + @expire, @token])
    end

    def unlock
      raise "You are trying to unlock a non locked mutex" unless @token

      # Since it's possible that the operations in the critical section took a long time,
      # we can't just simply release the lock. The unlock method checks if the unique @token
      # remains the same, and do not release if the lock token was overwritten.
      @@unlock_script ||= Script.new <<-LUA
        local key = KEYS[1]
        local lock_set = KEYS[2]
        local token = ARGV[1]
        local orig_key = ARGV[2]

        if redis.call('hget', key, 'token') == token then
          redis.call('del', key)
          if lock_set then
            redis.call('zrem', lock_set, orig_key)
          end
          return true
        else
          return false
        end
      LUA
      result = @@unlock_script.eval(@node, :keys => [@key, @lock_set].compact, :argv => [@token, @orig_key])
      @token = nil
      !!result
    end

    def still_locked?
      raise "You never locked that mutex" unless @token
      @node.hget(@key, 'token').to_i == @token
    end
  end
end
