require 'redis'
require 'redis/distributed'
require 'digest/sha1'

module Promiscuous::Redis
  def self.connect
    disconnect
    @master = new_connection
  end

  def self.master
    ensure_connected
    @master
  end

  def self.slave
    ensure_connected
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
      now = Time.now.to_i
      @expires_at = now + @expire + 1
      @token = Random.rand(1000000000)

      # This script loading is not thread safe (touching a class variable), but
      # that's okay, because the race is harmless.
      @@lock_script ||= Promiscuous::Redis::Script.new <<-SCRIPT
        local key = KEYS[1]
        local lock_set = KEYS[2]
        local now = tonumber(ARGV[1])
        local orig_key = ARGV[2]
        local expires_at = tonumber(ARGV[3])
        local token = ARGV[4]
        local lock_value = expires_at .. ':' .. token
        local old_value = redis.call('get', key)

        if old_value and tonumber(old_value:match("([^:]*):"):rep(1)) > now then return false end
        redis.call('set', key, lock_value)
        if lock_set then redis.call('zadd', lock_set, now, orig_key) end

        if old_value then return 'recovered' else return true end
      SCRIPT
      result = @@lock_script.eval(@node, :keys => [@key, @lock_set].compact, :argv => [now, @orig_key, @expires_at, @token])
      return :recovered if result == 'recovered'
      !!result
    end

    def extend
      @expires_at = Time.now + @expire + 1
      @node.set(@key, "#{@expires_at}:#{@token}")
    end

    def unlock
      # Since it's possible that the operations in the critical section took a long time,
      # we can't just simply release the lock. The unlock method checks if @expires_at
      # remains the same, and do not release when the lock timestamp was overwritten.
      @@unlock_script ||= Promiscuous::Redis::Script.new <<-SCRIPT
        local key = KEYS[1]
        local lock_set = KEYS[2]
        local orig_key = ARGV[1]
        local expires_at = ARGV[2]
        local token = ARGV[3]
        local lock_value = expires_at .. ':' .. token

        if redis.call('get', key) == lock_value then
          redis.call('del', key)
          if lock_set then redis.call('zrem', lock_set, orig_key) end
          return true
        else
          return false
        end
      SCRIPT
      @@unlock_script.eval(@node, :keys => [@key, @lock_set].compact, :argv => [@orig_key, @expires_at, @token])
    end

    def still_locked?
      @node.get(@key) == "#{@expires_at}:#{@token}"
    end
  end
end
