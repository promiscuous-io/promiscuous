module ::Containers; end
require 'containers/priority_queue'

class Promiscuous::Subscriber::Worker::MessageSynchronizer
  RECONNECT_INTERVAL = 2
  CLEANUP_INTERVAL   = 100 # messages
  QUEUE_MAX_AGE      = 100 # messages

  attr_accessor :redis, :node_synchronizers, :num_processed_messages, :num_queued_messages

  def initialize(root)
    @root = root
    @node_synchronizers = {}
    @lock = Mutex.new
    @reconnect_timer = Promiscuous::Timer.new("redis", RECONNECT_INTERVAL) { reconnect }
  end

  def connected?
    !!@redis
  end

  def connect
    @lock.synchronize do
      return unless !connected?

      @num_processed_messages = 0
      @num_queued_messages = 0
      redis = Promiscuous::Redis.new_blocking_connection
      redis.nodes.each { |node| @node_synchronizers[node] = NodeSynchronizer.new(self, node) }
      @redis = redis
    end
    @root.pump.recover
  end

  def disconnect
    @lock.synchronize do
      return unless connected?

      @redis, redis = nil, @redis
      @node_synchronizers.values.each { |node_synchronizer| node_synchronizer.stop_main_loop }
      @node_synchronizers.clear
      redis.quit
    end
  rescue Exception
  end

  def reconnect
    self.disconnect
    self.connect
    @reconnect_timer.reset
    Promiscuous.warn "[redis] Reconnected"
  end

  def rescue_connection(node, exception)
    # TODO stop the pump to unack all messages
    @reconnect_timer.start

    e = Promiscuous::Redis.lost_connection_exception(node, :inner => exception)
    Promiscuous.warn "[redis] #{e}. Reconnecting..."
    Promiscuous::Config.error_notifier.try(:call, e)
  end

  # process_when_ready() is called by the AMQP pump. This is what happens:
  # 1. First, we subscribe to redis and wait for the confirmation.
  # 2. Then we check if the version in redis is old enough to process the message.
  #    If not we bail out and rely on the subscription to kick the processing.
  # Because we subscribed in advanced, we will not miss the notification.
  def process_when_ready(msg)
    # Dropped messages will be redelivered as we (re)connect
    return unless self.redis

    @lock.synchronize do
      @num_queued_messages += 1
    end

    if msg.has_dependencies?
      process_message_proc = proc { process_message!(msg) }
      msg.happens_before_dependencies.reduce(process_message_proc) do |chain, dep|
        get_redis = dep.redis_node
        subscriber_redis = dep.redis_node(@redis)

        key = dep.key(:sub).join('rw').to_s
        version = dep.version
        node_synchronizer = @node_synchronizers[subscriber_redis]
        proc { node_synchronizer.on_version(subscriber_redis, get_redis, key, version, msg) { chain.call } }
      end.call
    else
      process_message!(msg)
    end
  end

  def process_message!(msg)
    @root.runner.messages_to_process << msg

    cleanup = false
    @lock.synchronize do
      @num_queued_messages -= 1
      @num_processed_messages += 1
      cleanup = @num_processed_messages % CLEANUP_INTERVAL == 0
    end
    @node_synchronizers.values.each(&:cleanup_if_old) if @node_synchronizers && cleanup
  end

  def maybe_recover
    if @num_queued_messages == Promiscuous::Config.prefetch
      # We've reached the amount of messages the amqp queue is willing to give us.
      # We also know that we are not processing messages (@num_queued_messages is
      # decremented before we send the message to the runners), and we are called
      # after adding a pending callback.
      recover
    end
  end

  def recover
    # XXX This recovery mechanism only works with one worker.
    # We are taking the earliest message to unblock, but in reality we should
    # do the DAG of the happens before dependencies, take root nodes
    # of the disconnected graphs, and sort by timestamps if needed.
    msg = blocked_messages.first

    versions_to_skip = msg.happens_before_dependencies.map do |dep|
      key = dep.key(:sub).join('rw').to_s
      to_skip = dep.version - dep.redis_node.get(key).to_i
      [dep, key, to_skip] if to_skip > 0
    end.compact

    return not_recovering if versions_to_skip.blank?

    recovery_msg = "Skipping "
    recovery_msg += versions_to_skip.map do |dep, key, to_skip|
      dep.redis_node.set(key, dep.version)
      dep.redis_node.publish(key, dep.version)

      # Note: the skipped message would have a write dependency with dep.to_s
      "#{to_skip} message(s) on #{dep}"
    end.join(", ")

    e = Promiscuous::Error::Recovery.new(recovery_msg)
    Promiscuous.error "[synchronization recovery] #{e}"
    # TODO Don't report when doing the initial sync
    Promiscuous::Config.error_notifier.try(:call, e)
  end

  def blocked_messages
    @node_synchronizers.values
      .map { |node_synchronizer| node_synchronizer.blocked_messages }
      .flatten
      .uniq
      .sort_by { |msg| msg.timestamp }
  end

  def not_recovering
    Promiscuous.warn "[synchronization recovery] Nothing to recover from"
  end

  class NodeSynchronizer
    attr_accessor :node, :subscriptions, :root_synchronizer

    def initialize(root_synchronizer, node)
      @root_synchronizer = root_synchronizer
      @node = node
      @subscriptions = {}
      @subscriptions_lock = Mutex.new
      @thread = Thread.new { main_loop }
    end

    def main_loop
      redis_client = @node.client

      loop do
        reply = redis_client.read
        raise reply if reply.is_a?(Redis::CommandError)
        type, subscription, arg = reply

        case type
        when 'subscribe'
          notify_subscription(subscription)
        when 'unsubscribe'
        when 'message'
          notify_key_change(subscription, arg)
        end
      end
    rescue EOFError, Errno::ECONNRESET => e
      # Unwanted disconnection
      @root_synchronizer.rescue_connection(redis_client, e) unless @stop
    rescue Exception => e
      unless @stop
        Promiscuous.warn "[redis] #{e.class} #{e.message}"
        Promiscuous.warn "[redis] #{e} #{e.backtrace.join("\n")}"

        Promiscuous::Config.error_notifier.try(:call, e)
      end
    end

    def stop_main_loop
      @stop = true
      @thread.kill
    end

    def on_version(subscriber_redis, get_redis, key, version, message, &callback)
      # subscriber_redis and get_redis are different connections to the
      # same node.
      if version == 0
        callback.call
      else
        sub = get_subscription(subscriber_redis, get_redis, key)
        sub.subscribe
        sub.add_callback(Subscription::Callback.new(version, callback, message))
      end
    end

    def blocked_messages
      @subscriptions_lock.synchronize do
        @subscriptions.values
          .map(&:callbacks)
          .map(&:next)
          .compact
          .map(&:message)
      end
    end

    def notify_subscription(key)
      find_subscription(key).try(:finalize_subscription)
    end

    def notify_key_change(key, version)
      find_subscription(key).try(:signal_version, version)
    end

    def remove_subscription(key)
      @subscriptions_lock.synchronize do
        @subscriptions.delete(key)
      end
    end

    def find_subscription(key)
      @subscriptions_lock.synchronize do
        @subscriptions[key]
      end
    end

    def get_subscription(subscriber_redis, get_redis, key)
      @subscriptions_lock.synchronize do
        @subscriptions[key] ||= Subscription.new(self, subscriber_redis, get_redis, key)
      end
    end

    def cleanup_if_old
      @subscriptions_lock.synchronize do
        @subscriptions.values.each(&:cleanup_if_old)
      end
    end

    class Subscription
      attr_accessor :node_synchronizer, :subscriber_redis, :get_redis, :key, :callbacks, :last_version

      def initialize(node_synchronizer, subscriber_redis, get_redis, key)
        self.node_synchronizer = node_synchronizer
        self.subscriber_redis = subscriber_redis
        self.get_redis = get_redis
        self.key = key

        @subscription_requested = false
        # We use a priority queue that returns the smallest value first
        @callbacks = Containers::PriorityQueue.new { |x, y| x < y }
        @last_version = 0
        @lock = Mutex.new

        refresh_activity
      end

      def total_num_processed_messages
        node_synchronizer.root_synchronizer.num_processed_messages
      end

      def refresh_activity
        @last_activity_at = total_num_processed_messages
      end

      def is_old?
        delta = total_num_processed_messages - @last_activity_at
        @callbacks.empty? && delta >= QUEUE_MAX_AGE
      end

      def cleanup_if_old
        if is_old?
          subscriber_redis.client.process([[:unsubscribe, key]])
          node_synchronizer.subscriptions.delete(key) # lock is already held
        end
      end

      def subscribe
        @lock.synchronize do
          return if @subscription_requested
          @subscription_requested = true
        end

        subscriber_redis.client.process([[:subscribe, key]])
      end

      def finalize_subscription
        signal_version(get_redis.get(key))
      end

      def signal_version(current_version)
        current_version = current_version.to_i
        @lock.synchronize do
          return if current_version < @last_version
          @last_version = current_version
        end

        loop do
          next_cb = nil
          @lock.synchronize do
            next_cb = @callbacks.next
            return unless next_cb && next_cb.can_perform?(@last_version)
            @callbacks.pop
          end
          next_cb.perform
        end
      end

      def add_callback(callback)
        refresh_activity

        can_perform_immediately = false
        @lock.synchronize do
          if callback.can_perform?(@last_version)
            can_perform_immediately = true
          else
            @callbacks.push(callback, callback.version)
          end
        end

        if can_perform_immediately
          callback.perform
        else
          node_synchronizer.root_synchronizer.maybe_recover if Promiscuous::Config.recovery
        end
      end

      class Callback < Struct.new(:version, :callback, :message)
        # message is just here for debugging, not used in the happy path
        def can_perform?(current_version)
          # The message synchronizer takes care of happens before dependencies.
          current_version >= self.version
        end

        def perform
          callback.call
        end
      end
    end
  end
end
