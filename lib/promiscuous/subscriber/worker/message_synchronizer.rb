require 'thread'

class Promiscuous::Subscriber::Worker::MessageSynchronizer
  class AbortThread < RuntimeError; end

  attr_accessor :redis

  def initialize
    @subscriptions = {}
    @subscriptions_lock = Mutex.new
  end

  def resume
    self.redis = Promiscuous::Redis.new_connection
    @thread = Thread.new { main_loop }
  end

  def redis_client
    redis.client.instance_variable_get('@client')
  end

  def redis_client_call(*args)
    redis_client.process([args])
  end

  def stop
    if Thread.current != @thread
      @thread.raise AbortThread
      @thread.join
      @thread = nil
    end
    self.redis = nil
    @subscriptions = {}
  end

  def main_loop
    redis.subscribe('dummy') do |on|
      on.subscribe do |subscription, num_subscriptions|
        find_subscription(subscription).finalize_subscription unless subscription == 'dummy'
      end

      on.message do |subscription, message|
        find_subscription(subscription).maybe_perform_callbacks(message)
      end

      on.unsubscribe do |subscription, num_subscriptions|
      end
    end
  rescue AbortThread
  rescue Exception => e
    Promiscuous.warn "[redis] #{e} #{e.backtrace.join("\n")}"

    e = Promiscuous::Error::Connection.new(:redis, 'Lost connection')
    Promiscuous::Worker.stop
    Promiscuous::Config.error_notifier.try(:call, e)
  end

  def process_when_ready(msg)
    return msg.process unless msg.has_version?

    on_version Promiscuous::Redis.sub_key('global'), msg.version[:global] do
      msg.process
    end
  end

  def on_version(key, version, &callback)
    cb = Subscription::Callback.new(version, callback)
    get_subscription(key).subscribe.add_callback(version, cb)
    cb.maybe_perform(Promiscuous::Redis.get(key))
  end

  def find_subscription(key)
    @subscriptions_lock.synchronize do
      raise "Fatal error (redis sub)" unless @subscriptions[key]
      @subscriptions[key]
    end
  end

  def get_subscription(key)
    @subscriptions_lock.synchronize do
      @subscriptions[key] ||= Subscription.new(self, key)
    end
  end

  class Subscription
    attr_accessor :parent, :key

    def initialize(parent, key)
      self.parent = parent
      self.key = key

      @callbacks = {}
      @callbacks_lock = Mutex.new
      @subscribed_to_redis = ConditionVariable.new
    end

    def subscribe
      @callbacks_lock.synchronize do
        parent.redis_client_call(:subscribe, key)
        @subscribed_to_redis.wait(@callbacks_lock)
      end
      self
    end

    def finalize_subscription
      @callbacks_lock.synchronize do
        @subscribed_to_redis.broadcast
      end
    end

    def destroy
      # TODO parent.redis_client_call(:unsubscribe, key)
    end

    def add_callback(version, callback)
      callback.subscription = self
      @callbacks_lock.synchronize do
        @callbacks[callback.token] = callback
      end
    end

    def remove_callback(token)
      @callbacks_lock.synchronize do
        !!@callbacks.delete(token)
      end
      # TODO unsubscribe after a while?
    end

    def find_first_performable_callback(current_version)
      @callbacks_lock.synchronize do
        @callbacks.values.each do |cb|
          return cb if cb.can_perform?(current_version)
        end
      end
      nil
    end

    def maybe_perform_callbacks(current_version)
      loop do
        cb = find_first_performable_callback(current_version)
        break if cb.nil?
        cb.perform
      end
    end

    class Callback
      cattr_accessor :token_lock, :token
      self.token_lock = Mutex.new
      self.token = 0

      def self.get_internal_token
        self.token_lock.synchronize do
          self.token += 1
        end
      end

      attr_accessor :subscription, :version, :callback

      def initialize(version, callback)
        self.version = version
        self.callback = callback
        @token = self.class.get_internal_token
      end

      def can_perform?(current_version)
        current_version.to_i + 1 >= self.version
      end

      def perform
        callback.call if subscription.remove_callback(@token)
      end

      def maybe_perform(current_version)
        perform if can_perform?(current_version)
      end
    end
  end
end
