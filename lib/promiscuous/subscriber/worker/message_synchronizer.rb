module ::Containers; end
require 'containers/priority_queue'

class Promiscuous::Subscriber::Worker::MessageSynchronizer
  include Celluloid::IO

  attr_accessor :redis

  def initialize
    connect
    main_loop!
  end

  def stop
    terminate
  end

  def finalize
    disconnect
  end

  def connect
    @queued_messages = 0
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
    @reconnect_timer ||= after(2.seconds) { reconnect }
  end

  def main_loop
    redis_client = self.redis.client
    loop do
      reply = redis_client.read
      raise reply if reply.is_a?(Redis::CommandError)
      type, subscription, arg = reply

      case type
      when 'subscribe'
        find_subscription(subscription).finalize_subscription
      when 'unsubscribe'
      when 'message'
        find_subscription(subscription).signal_version(arg)
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
  # Because we subscribed in advanced, we will not miss the notification, but
  # extra care needs to be taken to avoid processing the message twice (see
  # perform()).
  def process_when_ready(msg)
    # Dropped messages will be redelivered as we reconnect
    # when calling worker.pump.start
    return unless self.redis

    bump_message_counter!

    return process_message!(msg) unless msg.has_dependencies?

    # The message synchronizer only takes care of happens before (>=) dependencies.
    # The message will handle the skip logic in case of duplicates.
    on_version Promiscuous::Redis.sub_key('global'), msg.global_version do
      process_message!(msg)
    end
  end

  def bump_message_counter!
    @queued_messages += 1
    maybe_recover
  end

  def maybe_recover
    return unless Promiscuous::Config.recovery

    if @queued_messages == Promiscuous::Config.prefetch
      # We've reached the amount of messages the amqp queue is willing to give us.
      # We also know that we are not processing messages (@queued_messages is
      # decremented before we send the message to the runners).
      recover
    end
  end

  def recover
    global_key = Promiscuous::Redis.sub_key('global')
    current_version = Promiscuous::Redis.get(global_key).to_i

    version_to_allow_progress = get_subscription(global_key).callbacks.next.version - 1
    num_messages_to_skip = version_to_allow_progress - current_version

    if num_messages_to_skip > 0
      recovery_msg = "Recovering. Moving current version from #{current_version} " +
                     "to #{version_to_allow_progress}. " +
                     "Skipping #{num_messages_to_skip} messages..."
    else
      recovery_msg = "Not recovering. current version is #{current_version}, " +
                     "while we just need #{version_to_allow_progress}. " +
                     "Offset is #{num_messages_to_skip} message."
    end

    e = Promiscuous::Error::Recover.new(recovery_msg)
    if current_version > 0
      Promiscuous.error "[receive] #{e}"
      Promiscuous::Config.error_notifier.try(:call, e)
    else
      Promiscuous.info "[receive] #{e}"
      # Initial sync, nothing to worry about
    end

    if num_messages_to_skip > 0
      Promiscuous::Redis.set(global_key, version_to_allow_progress)
      Promiscuous::Redis.publish(global_key, version_to_allow_progress)
    end
  end

  def process_message!(msg)
    @queued_messages -= 1
    Celluloid::Actor[:runners].process!(msg)
  end

  def on_version(key, version, &callback)
    return unless @subscriptions
    sub = get_subscription(key).subscribe
    sub.add_callback(Subscription::Callback.new(version, callback))
    sub.signal_version(Promiscuous::Redis.get(key))
  end

  def find_subscription(key)
    raise "Fatal error (redis sub)" unless @subscriptions[key]
    @subscriptions[key]
  end

  def get_subscription(key)
    @subscriptions[key] ||= Subscription.new(self, key)
  end

  class Subscription
    attr_accessor :parent, :key, :callbacks

    def initialize(parent, key)
      self.parent = parent
      self.key = key

      @subscription_requested = false
      @subscribed_to_redis = false
      # We use a priority queue that returns the smallest value first
      @callbacks = Containers::PriorityQueue.new { |x, y| x < y }
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

    def destroy
      # TODO parent.redis_client_call(:unsubscribe, key)
    end

    def signal_version(current_version)
      current_version = current_version.to_i
      loop do
        next_cb = @callbacks.next
        return unless next_cb && next_cb.can_perform?(current_version)

        @callbacks.pop
        next_cb.perform
      end
    end

    def add_callback(callback)
      callback.subscription = self
      @callbacks.push(callback, callback.version)
    end

    class Callback
      attr_accessor :subscription, :version, :callback, :token

      def initialize(version, callback)
        self.version = version
        self.callback = callback
      end

      def can_perform?(current_version)
        current_version + 1 >= self.version
      end

      def perform
        callback.call
      end
    end
  end
end
