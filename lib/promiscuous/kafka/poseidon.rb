class Promiscuous::Kafka::Poseidon
  def self.hijack_poseidon
    return if @poseidon_hijacked
    ::Poseidon::Connection.class_eval do
      alias_method :raise_connection_failed_error_without_promiscuous, :raise_connection_failed_error

      def raise_connection_failed_error
        Promiscuous.warn "[amqp] #{e}. Reconnecting..."
        Promiscuous::Config.error_notifier.call(e)
        raise_connection_failed_error
      end
    end
    @poseidon_hijacked = true
  end

  attr_accessor :connection, :connection_lock

  def initialize_driver
    require 'poseidon'
    self.class.hijack_poseidon
  end

  def initialize
    initialize_driver
    # The poseidon socket doesn't like when multiple threads access to it apparently
    @connection_lock = Mutex.new
  end

  def new_connection
    # TODO: might have to go to a lower level than this, Producers and
    # Subscribers need to use different libraries
    connection = ::Poseidon::Producer.new(Promiscuous::Config.kafka_hosts, "promiscuous.#{Promiscuous::Config.app}",
                                          :type => :sync,
                                          :compression_codec => :none,
                                          :metadata_refresh_interval_ms => 600_000,
                                          :max_send_retries => 10,
                                          :retry_backoff_ms => 100,
                                          :required_acks => 1,
                                          :ack_timeout_ms => 1000,
                                          :socket_timeout_ms => Promiscuous::Config.socket_timeout)
    # connection.start
    connection
  end

  def connect
    @connection = new_connection
  end

  def disconnect
    @connection_lock.synchronize do
      return unless connected?
      @connection.shutdown
      @connection = nil
    end
  end

  #TODO: broken
  def connected?
    !!@connection.try(:connected?)
  end

  def raw_publish(options)
    @connection.send_messages([Poseidon::MessageToSend.new(options[:topic], options[:payload], options[:key])])
  end

  def publish(options={})
    Promiscuous.debug "[publish] #{options[:topic]}/#{options[:key]} #{options[:payload]}"

    @connection_lock.synchronize do
      raw_publish(options)
    end
  rescue Exception => e
    Promiscuous.warn("[publish] Failure publishing to kafka #{e}\n#{e.backtrace.join("\n")}")
    e = Promiscuous::Error::Publisher.new(e, :payload => options[:payload])
    Promiscuous::Config.error_notifier.call(e)
  end

  module Subscriber
    def subscribe(options={}, &block)
      require 'poseidon_cluster'


      @connection = Poseidon::ConsumerGroup.new(Promiscuous::Config.app,
                                             Promiscuous::Config.kafka_hosts,
                                             Promiscuous::Config.zookeeper_hosts,
                                             Promiscuous::Config.topic)
      @lock = Mutex.new
      @subscription = subscribe_topic(@queue, &block)
    end

    def subscribe_topic(queue, &block)
      # XXX: seems to get more than one message at a time
      @connection.fetch_loop(:commit => false) do |partition, payloads|
        payloads.each do |payload|
          Promiscuous.debug "[subscribe] Fetched '#{payload.value}' at #{payload.offset} from #{partition}"
          block.call(MetaData.new(self, partition, payload.offset), payload)
        end
      end
    end

    def delete_queues
      # TODO: implement, possibly keep inside of the specs
      # [@error_queue, @queue].each { |queue| queue.try(:delete) }
    end

    class MetaData
      def initialize(subscriber, partition, offset)
        @subscriber = subscriber
        @partition = partition
        @offset = offset
      end

      def ack
        @subscriber.advance_offset(@offset)
      end
    end

    def advance_offset(offset)
      @lock.synchronize { @connection.commit(@partition, offset) }
    end

    def disconnect
      @lock.synchronize { @connection.close }
    end
  end
end
