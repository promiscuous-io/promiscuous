class Promiscuous::Subscriber::Worker::MessageSynchronizer
  class AbortThread < RuntimeError; end

  attr_accessor :worker, :redis

  # The Subscription class needs this (see subscribe())
  attr_accessor :state_lock, :subscriptions, :subscriptions_signal

  def initialize(worker)
    self.worker = worker
    @subscriptions = {}
    @subscriptions_lock = Mutex.new
    @state_lock = Mutex.new
    @subscriptions_signal = ConditionVariable.new
  end

  # Even though resume/stop are synchronized by the caller,
  # we need to take the state_lock to synchronize on various things
  def resume
    @state_lock.synchronize do
      # We need to connect to redis before going in the main loop, so we can
      # accept requests while the thread is launching, and send subscriptions
      # requests to redis.
      self.redis = Promiscuous::Redis.new_connection
      @subscriptions = {}
      @kill_with_exception = false
      @thread = Thread.new { main_loop }
    end
  end

  def stop
    return if Thread.current == @thread

    @state_lock.synchronize do
      # we need to synchronize with redis_blocking_read
      # to avoid throwing an exception at a random place.
      @thread.raise AbortThread if @kill_with_exception
    end
    @thread.join
  ensure
    @thread = nil
  end

  def redis_blocking_read
    # It would be nice to convert this loop to use async IO...
    @state_lock.synchronize { @kill_with_exception = true }
    # Synchronize with stop(). The locks are acting more like barriers than
    # locking primitives.
    raise AbortThread if worker.stopped?
    reply = redis.client.without_socket_timeout { redis.client.read }
    @state_lock.synchronize { @kill_with_exception = false }
    reply
  end

  def main_loop
    # We cannot use Redis subscribers loop because of the exception issue.
    loop do
      reply = redis_blocking_read
      raise reply if reply.is_a?(Redis::CommandError)
      type, subscription, arg = reply

      case type
      when 'subscribe'
        @state_lock.synchronize do
          find_subscription(subscription).finalize_subscription
          @subscriptions_signal.broadcast
        end
      when 'unsubscribe'
      when 'message'
        find_subscription(subscription).maybe_perform_callbacks(arg)
      end
    end
  rescue AbortThread
  rescue Exception => e
    Promiscuous.warn "[redis] #{e} #{e.backtrace.join("\n")}"

    e = Promiscuous::Error::Connection.new(:redis, 'Lost connection')
    Promiscuous::Worker.stop
    Promiscuous::Config.error_notifier.try(:call, e)
  ensure
    @state_lock.synchronize do
      # @subscriptions is synchronized with on_version() to prevent further
      # subscriptions.
      # Furthermore, @subscriptions being nil is used to indicate to waiters in
      # subscribe() that they will never complete.
      @subscriptions = nil
      @subscriptions_signal.broadcast

      # synchronizing this may seem superfluous, but it's not. if the thread
      # initiate the stop, we could see an early resume() call.
      self.redis.client.connection.disconnect rescue nil
      self.redis = nil
    end
  end

  # process_when_ready() is called by the AMQP pump. This is what happens:
  # 1. First, we subscribe to redis and wait for the confirmation.
  # 2. Then we check if the version in redis is old enough to process the message.
  #    If not we bail out and rely on the subscription to kick the processing.
  # Because we subscribed in advanced, we will not miss the notification, but
  # extra care needs to be taken to avoid processing the message twice (see
  # perform()).
  # Note that this method is tolerant from being called by two threads
  # requesting the same subscription.
  def process_when_ready(msg)
    return msg.process unless msg.has_version?

    on_version Promiscuous::Redis.sub_key('global'), msg.version[:global] do
      msg.process
    end
  end

  def on_version(key, version, &callback)
    cb = Subscription::Callback.new(version, callback)

    @state_lock.synchronize do
      return if @subscriptions.nil?
      # @subscriptions will never change under our feets because we hold the
      # state lock synchronizing with the thread exiting.
      get_subscription(key).subscribe.add_callback(version, cb)
    end

    cb.maybe_perform(Promiscuous::Redis.get(key))
  end

  # state_lock must be taken before calling find_subscription()
  def find_subscription(key)
    raise "Fatal error (redis sub)" unless @subscriptions[key]
    @subscriptions[key]
  end

  # state_lock must be taken before calling find_subscription()
  def get_subscription(key)
    @subscriptions[key] ||= Subscription.new(self, key)
  end

  class Subscription
    attr_accessor :parent, :key

    def initialize(parent, key)
      self.parent = parent
      self.key = key

      @subscription_requested = false
      @subscribed_to_redis = false
      @callbacks = {}
      @callbacks_lock = Mutex.new
    end

    # subscribe() is called with the state_lock of the parent held
    def subscribe
      loop do
        # If someone else subscribed for us, we are good.
        break if @subscribed_to_redis

        # We will never get our subscription finalized if subscriptions is nil,
        # The worker is dying, and we got here by chance.
        break if parent.subscriptions.nil?

        request_subscription
        parent.subscriptions_signal.wait(parent.state_lock)
      end
      self
    end

    def request_subscription
      # We will not send two subscription requests, since we are holding
      # the state_lock of the parent.
      return if @subscription_requested
      parent.redis.client.process([[:subscribe, key]])
      @subscription_requested = true
    end

    def finalize_subscription
      @subscribed_to_redis = true
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

        # We cannot hold the @callbacks_lock when performing the callback,
        # because it might block, hence the loop.
        cb.perform
      end
    end

    class Callback
      # Tokens are only used so that the callback can find and remove itself
      # in the callback list.
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
        # removing the callback can happen only once, ensuring that the
        # callback is called at most once.
        callback.call if subscription.remove_callback(@token)
      end

      def maybe_perform(current_version)
        perform if can_perform?(current_version)
      end
    end
  end
end
