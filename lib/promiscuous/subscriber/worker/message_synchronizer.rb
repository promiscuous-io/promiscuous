module ::Containers; end
require 'containers/priority_queue'

class Promiscuous::Subscriber::Worker::MessageSynchronizer
  include Celluloid::IO

  RECONNECT_INTERVAL = 2.seconds
  CLEANUP_INTERVAL   = 1.minute
  QUEUE_MAX_AGE      = 10.minutes

  attr_accessor :redis, :subscriptions

  def initialize
    connect
    async.main_loop
    cleanup_later
  end

  def stop
    terminate
  end

  def finalize
    disconnect
  end

  def connect
    @num_queued_messages = 0
    @subscriptions = {}
    self.redis = Promiscuous::Redis.new_celluloid_connection
  end

  def connected?
    !!self.redis
  end

  def rescue_connection
    disconnect
    e = Promiscuous::Redis.lost_connection_exception

    Promiscuous.warn "[redis] #{e}. Reconnecting..."
    Promiscuous::Config.error_notifier.try(:call, e)

    # TODO stop the pump to unack all messages
    reconnect_later
  end

  def disconnect
    self.redis.client.connection.disconnect if connected?
  rescue
  ensure
    @subscriptions = {}
    self.redis = nil
  end

  def reconnect
    @reconnect_timer.try(:reset)
    @reconnect_timer = nil

    unless connected?
      self.connect
      main_loop!

      Promiscuous.warn "[redis] Reconnected"
      Celluloid::Actor[:pump].recover
    end
  rescue
    reconnect_later
  end

  def reconnect_later
    @reconnect_timer ||= after(RECONNECT_INTERVAL) { reconnect }
  end

  def cleanup
    @subscriptions.values.each(&:cleanup_if_old)
    cleanup_later
  end

  def cleanup_later
    after(CLEANUP_INTERVAL) { cleanup }
  end

  def main_loop
    redis_client = self.redis.client
    loop do
      reply = redis_client.read
      raise reply if reply.is_a?(Redis::CommandError)
      type, subscription, arg = reply

      case type
      when 'subscribe'
        async.notify_subscription(subscription)
      when 'unsubscribe'
      when 'message'
        async.notify_key_change(subscription, arg)
      end
    end
  rescue EOFError
    # Unwanted disconnection
    rescue_connection
  rescue IOError => e
    unless redis_client == self.redis.client
      # We were told to disconnect
    else
      raise e
    end
  rescue Celluloid::Task::TerminatedError
  rescue Exception => e
    Promiscuous.warn "[redis] #{e} #{e.backtrace.join("\n")}"

    #Promiscuous::Worker.stop TODO
    Promiscuous::Config.error_notifier.try(:call, e)
  end

  # process_when_ready() is called by the AMQP pump. This is what happens:
  # 1. First, we subscribe to redis and wait for the confirmation.
  # 2. Then we check if the version in redis is old enough to process the message.
  #    If not we bail out and rely on the subscription to kick the processing.
  # Because we subscribed in advanced, we will not miss the notification.
  def process_when_ready(msg)
    # Dropped messages will be redelivered as we reconnect
    # when calling worker.pump.start
    return unless self.redis

    @num_queued_messages += 1

    if msg.has_dependencies?
      msg.happens_before_dependencies.reduce(proc { process_message!(msg) }) do |chain, dep|
        proc { on_version(dep.key(:sub).for(:redis), dep.version, msg) { chain.call } }
      end.call
    else
      process_message!(msg)
    end
  end

  def process_message!(msg)
    @num_queued_messages -= 1
    Celluloid::Actor[:runners].async.process(msg)
  end

  def on_version(key, version, message, &callback)
    return unless @subscriptions
    sub = get_subscription(key).subscribe
    sub.add_callback(Subscription::Callback.new(version, callback, message))
  end

  def maybe_recover
    if Promiscuous::Config.recovery && should_recover?
      # We've reached the amount of messages the amqp queue is willing to give us.
      # We also know that we are not processing messages (@num_queued_messages is
      # decremented before we send the message to the runners), and we are called
      # after adding a pending callback.
      recover
    end
  end

  def should_recover?
    @num_queued_messages == Promiscuous::Config.prefetch
  end

  def recover
    # XXX This recovery mechanism only works with one worker.
    # We are taking the earliest message to unblock, but in reality we should
    # do the DAG of the happens before dependencies, take root nodes
    # of the disconnected graphs, and sort by timestamps if needed.
    msg = blocked_messages.first

    versions_to_skip = msg.happens_before_dependencies.map do |dep|
      key = dep.key(:sub).for(:redis)
      to_skip = dep.version - Promiscuous::Redis.get(key).to_i
      [dep, key, to_skip] if to_skip > 0
    end.compact

    return not_recovering if versions_to_skip.blank?

    recovery_msg = "Skipping "
    recovery_msg += versions_to_skip.map do |dep, key, to_skip|
      Promiscuous::Redis.set(key, dep.version)
      Promiscuous::Redis.publish(key, dep.version)

      # Note: the skipped message would have a write dependency with dep.to_s
      "#{to_skip} message(s) on #{dep}"
    end.join(", ")

    e = Promiscuous::Error::Recover.new(recovery_msg)
    Promiscuous.error "[receive] #{e}"
    # TODO Don't report when doing the initial sync
    Promiscuous::Config.error_notifier.try(:call, e)
  end

  def not_recovering
    Promiscuous.warn "[receive] Nothing to recover from"
  end

  def blocked_messages
    @subscriptions.values
      .map(&:callbacks)
      .map(&:next)
      .compact
      .map(&:message)
      .uniq
      .sort_by { |msg| msg.timestamp }
  end

  def notify_subscription(key)
    find_subscription(key).finalize_subscription
  end

  def notify_key_change(key, version)
    find_subscription(key).signal_version(version)
  end

  def try_notify_key_change(key, version)
    notify_key_change(key, version) if @subscriptions[key]
  end

  def find_subscription(key)
    raise "Fatal error (redis sub)" unless @subscriptions[key]
    @subscriptions[key]
  end

  def get_subscription(key)
    @subscriptions[key] ||= Subscription.new(self, key)
  end

  class Subscription
    attr_accessor :parent, :key, :callbacks, :last_version

    def initialize(parent, key)
      self.parent = parent
      self.key = key

      @subscription_requested = false
      @subscribed_to_redis = false
      # We use a priority queue that returns the smallest value first
      @callbacks = Containers::PriorityQueue.new { |x, y| x < y }
      @last_version = 0

      refresh_activity
    end

    def refresh_activity
      @last_activity_at = Time.now
    end

    def is_old?
      delta = Time.now - @last_activity_at
      @callbacks.empty? && delta > QUEUE_MAX_AGE
    end

    def cleanup_if_old
      if is_old?
        parent.redis.client.process([[:unsubscribe, key]])
        parent.subscriptions.delete(key)
      end
    end

    def subscribe
      request_subscription

      loop do
        break if @subscribed_to_redis
        parent.wait :subscription
      end
      self
    end

    def request_subscription
      return if @subscription_requested
      parent.redis.client.process([[:subscribe, key]])
      @subscription_requested = true
    end

    def finalize_subscription
      @subscribed_to_redis = true
      parent.signal :subscription
    end

    def signal_version(current_version)
      current_version = current_version.to_i
      return if current_version < @last_version
      @last_version = current_version

      performed = false
      loop do
        next_cb = @callbacks.next
        break unless next_cb && next_cb.can_perform?(current_version)

        @callbacks.pop
        next_cb.perform
        performed = true
      end
      performed
    end

    def add_callback(callback)
      refresh_activity
      callback.subscription = self

      if callback.can_perform?(@last_version)
        callback.perform
      else
        @callbacks.push(callback, callback.version)
        unless signal_version(Promiscuous::Redis.get(key))
          parent.maybe_recover
        end
      end
    end

    class Callback < Struct.new(:version, :callback, :message, :subscription)
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
