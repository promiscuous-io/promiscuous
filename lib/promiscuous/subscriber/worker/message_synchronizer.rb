module ::Containers; end
require 'containers/priority_queue'

class Promiscuous::Subscriber::Worker::MessageSynchronizer
  include Celluloid::IO

  attr_accessor :redis

  def initialize
    connect
    async.main_loop
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
        notify_key_change(subscription, arg)
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

  def count_dependencies(deps)
    increments = {}
    deps.each do |dep|
      key = dep.key.for(:redis)
      increments[key] ||= 0
      increments[key] += 1
    end
    increments
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

    bump_message_counter!

    return process_message!(msg) unless msg.has_dependencies?

    # We wait for each link/read versions to be equal to what we received.
    # For write versions, since they represent the value of the corresponding
    # counters after all the increments, we have to figure out the version that
    # they would be before all the increments.
    read_increments = count_dependencies(msg.dependencies[:read])
    deps = []
    deps += msg.dependencies[:write].map do |dep|
      dep.dup.tap { |d| d.version -= 1 + read_increments[d.key.for(:redis)].to_i }
    end
    deps += msg.dependencies[:read]
    deps << msg.dependencies[:link] if msg.dependencies[:link]

    deps.reduce(proc { process_message!(msg) }) do |chain, dep|
      proc { on_version(dep.key.for(:redis), dep.version) { chain.call } }
    end.call
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
    raise NotImplementedError
  end

  def process_message!(msg)
    @queued_messages -= 1
    Celluloid::Actor[:runners].async.process(msg)
  end

  def on_version(key, version, &callback)
    return unless @subscriptions
    sub = get_subscription(key).subscribe
    cb = Subscription::Callback.new(version, callback)

    if sub.last_version && cb.can_perform?(sub.last_version)
      cb.perform
    else
      sub.add_callback(cb).signal_version(Promiscuous::Redis.get(key))
    end
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
      @last_version = current_version = current_version.to_i
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
      self
    end

    class Callback
      attr_accessor :subscription, :version, :callback, :token

      def initialize(version, callback)
        self.version = version
        self.callback = callback
      end

      def can_perform?(current_version)
        current_version >= self.version
      end

      def perform
        callback.call
      end
    end
  end
end
