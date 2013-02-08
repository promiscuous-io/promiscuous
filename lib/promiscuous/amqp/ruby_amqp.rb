require 'eventmachine'
require 'amqp'

module Promiscuous::AMQP::RubyAMQP
  class Synchronizer
    def initialize
      @mutex = Mutex.new
      @condition = ConditionVariable.new
      @signaled = false
    end

    def wait
      @mutex.synchronize do
        loop do
          return if @signaled
          @condition.wait(@mutex)
        end
      end
    end

    def signal
      @mutex.synchronize do
        @signaled = true
        @condition.signal
      end
    end
  end

  def self.maybe_start_event_machine
    return if EM.reactor_running?

    EM.error_handler { |e| Promiscuous::Config.error_notifier.try(:call, e) }
    em_sync = Synchronizer.new
    @event_machine_thread = Thread.new { EM.run { em_sync.signal } }
    em_sync.wait
  end

  def self.connect
    return if @connection

    @channels = {}
    @exchanges = {}

    maybe_start_event_machine

    amqp_options = if Promiscuous::Config.amqp_url
      url = URI.parse(Promiscuous::Config.amqp_url)
      raise "Please use amqp://user:password@host:port/vhost" if url.scheme != 'amqp'

      {
        :host      => url.host,
        :port      => url.port,
        :scheme    => url.scheme,
        :user      => url.user,
        :pass      => url.password,
        :vhost     => url.path.empty? ? "/" : url.path,
        :heartbeat => Promiscuous::Config.heartbeat
      }
    end

    channel_sync = Synchronizer.new
    ::AMQP.connect(amqp_options) do |connection|
      @connection = connection
      @connection.on_tcp_connection_loss do |conn|
        unless conn.reconnecting?
          e = Promiscuous::AMQP.lost_connection_exception
          Promiscuous.warn "[amqp] #{e}. Reconnecting..."
          Promiscuous::Config.error_notifier.try(:call, e)
          conn.periodically_reconnect(2.seconds)
        end
      end

      @connection.on_recovery do |conn|
        Promiscuous.warn "[amqp] Reconnected"
        @channels.values.each(&:recover) if conn == @connection
      end

      @connection.on_error do |conn, conn_close|
        # No need to handle CONNECTION_FORCED since on_tcp_connection_loss takes
        # care of it.
        Promiscuous.warn "[amqp] #{conn_close.reply_text}"
      end

      get_channel(:master) { channel_sync.signal }
    end
    channel_sync.wait
  rescue Exception => e
    self.disconnect
    raise e
  end

  def self.get_channel(name, &block)
    if @channels[name]
      yield(@channels[name]) if block_given?
      @channels[name]
    else
      options = {:auto_recovery => true, :prefetch => Promiscuous::Config.prefetch}
      ::AMQP::Channel.new(@connection, options) do |channel|
        @channels[name] = channel
        get_exchange(name)
        yield(channel) if block_given?
      end
    end
  end

  def self.close_channel(name, &block)
    EM.next_tick do
      channel = @channels.try(:delete, name)
      if channel
        channel.close(&block)
      else
        block.call if block
      end
    end
  end

  def self.disconnect
    @connection.close { EM.stop if @event_machine_thread } if @connection
    @event_machine_thread.join if @event_machine_thread
    @event_machine_thread = nil
    @connection = nil
    @channels = nil
    @exchanges = nil
  end

  def self.connected?
    @connection.connected? if @connection
  end

  def self.publish(options={})
    EM.next_tick do
      get_exchange(:master).publish(options[:payload], :routing_key => options[:key], :persistent  => true) do
      end
    end
  end

  def self.get_exchange(name)
    @exchanges[name] ||= get_channel(name).topic(Promiscuous::AMQP::EXCHANGE, :durable => true)
  end
end
