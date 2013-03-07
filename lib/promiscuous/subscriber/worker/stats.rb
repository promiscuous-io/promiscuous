class Promiscuous::Subscriber::Worker::Stats
  include Celluloid

  def initialize
    url = Promiscuous::Config.stats_redis_url
    @interval = Promiscuous::Config.stats_interval

    unless @interval.zero?
      @redis = Promiscuous::Redis.new_connection(url)
      key = Promiscuous::Key.new(:sub).join(Socket.gethostname)
      @key_processed_message = key.join('__stats__', 'processed_messages').for(:redis)
      @key_total_response_time = key.join('__stats__', 'total_response_time').for(:redis)

      @redis.set(@key_processed_message, 0)
      @redis.set(@key_total_response_time, 0)
      @last_aggregate = Time.now

      after(@interval) { STDERR.puts ""; aggregate_stats }
    end
  end

  def aggregate_stats
    processed_messages = nil
    total_response_time = nil
    @redis.multi do
      processed_messages = @redis.getset(@key_processed_message, 0)
      total_response_time = @redis.getset(@key_total_response_time, 0)
    end

    last_aggregate = @last_aggregate
    @last_aggregate = Time.now
    processed_messages = processed_messages.value.to_i
    total_response_time = total_response_time.value.to_i

    rate = sprintf("%.1f", processed_messages.to_f / (Time.now - last_aggregate))
    latency = "N/A"
    unless processed_messages.zero?
      latency = total_response_time.to_f / (1000 * processed_messages).to_f
      if latency > 2.minutes
        latency = sprintf("%.3fmin", latency / 1.minute)
      else
        latency = sprintf("%.3fsec", latency)
      end
    end
    STDERR.puts "\e[1A" + "\b" * 200 + "Messages: #{processed_messages}  Rate: #{rate} msg/s  Latency: #{latency}" + " " * 30

    after(@interval) { aggregate_stats }
  end

  def finalize
    @redis.client.disconnect rescue nil if @redis
  end

  def notify_processed_message(msg, time)
    return if msg.timestamp.zero? || !@redis

    msecs = (time.to_i * 1000 + time.usec / 1000).to_i - msg.timestamp
    @redis.pipelined do
      @redis.incr(@key_processed_message)
      @redis.incrby(@key_total_response_time, msecs)
    end
  end
end
