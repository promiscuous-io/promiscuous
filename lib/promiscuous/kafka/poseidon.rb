class Promiscuous::Kafka::Poseidon
  def self.hijack_poseidon
    return if @poseidon_hijacked
    ::Poseidon::Connection.class_eval do
      alias_method :raise_connection_failed_error_without_promiscuous, :raise_connection_failed_error

      def raise_connection_failed_error
        exception = Poseidon::Connection::ConnectionFailedError.new("Failed to connect to #{Promiscuous::Config.kafka_hosts}")
        Promiscuous.warn "[kafka] #{exception}. Reconnecting..."
        Promiscuous::Config.error_notifier.call(exception)
        raise exception
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
    # also, client id needs to be unique across the system, use hostname+rand?
    connection = ::Poseidon::Producer.new(Promiscuous::Config.kafka_hosts, "promiscuous.#{Promiscuous::Config.app}",
                                          :type => :sync,
                                          :compression_codec => :none,
                                          :metadata_refresh_interval_ms => 600_000,
                                          :max_send_retries => 10,
                                          :retry_backoff_ms => 100,
                                          :required_acks => 1,
                                          :ack_timeout_ms => 1000,
                                          :socket_timeout_ms => Promiscuous::Config.socket_timeout)
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

  # TODO: key needs to be based on the model and not just __all__
  def publish(options={})
    Promiscuous.debug "[publish] [kafka] #{options[:topic]}/#{options[:key]} #{options[:payload]}"

    @connection_lock.synchronize do
      raw_publish(options)
    end
  rescue Exception => e
    Promiscuous.warn("[publish] Failure publishing to kafka #{e}\n#{e.backtrace.join("\n")}")
    e = Promiscuous::Error::Publisher.new(e, :payload => options[:payload])
    Promiscuous::Config.error_notifier.call(e)
  end

  module Subscriber
    def subscribe(topic)
      require 'poseidon_cluster'

      @consumer = ::Poseidon::ConsumerGroup.new(Promiscuous::Config.app,
                                                Promiscuous::Config.kafka_hosts,
                                                Promiscuous::Config.zookeeper_hosts,
                                                topic, :trail => Promiscuous::Config.test_mode)
    end

    def fetch_and_process_messages(&block)
      # XXX: seems to get more than one message at a time
      Promiscuous.debug "[kafka] Fetching messages topic:#{@consumer.topic} #{Thread.current}"
      @consumer.fetch(:commit => false) do |partition, payloads|
        Promiscuous.debug "[kafka] Received #{payloads.count} payloads topic:#{@consumer.topic} #{Thread.current}"
        payloads.each do |payload|
          Promiscuous.debug "[kafka] Fetched '#{payload.value}' topic:#{@consumer.topic} offset:#{payload.offset} parition:#{partition}"
          block.call(MetaData.new(@consumer, partition, payload.offset), payload)
        end
      end
    end

    def delete_queues
      # TODO: implement, possibly keep inside of the specs
      # Promiscuous::Config.subscriber_topics.each { |queue| queue.try(:delete) }
    end

    class MetaData
      def initialize(consumer, partition, offset)
        @consumer = consumer
        @partition = partition
        @offset = offset

        Promiscuous.debug "[kafka] [metadata] topic:#{@consumer.topic} offset:#{offset} partition:#{partition}"
      end

      # TODO: rename to advance_offset or commit?
      def ack
        Promiscuous.debug "[kafka] [commit] topic:#{@consumer.topic} offset:#{@offset+1} partition:#{@partition}"
        @consumer.commit(@partition, @offset+1)
      end
    end

    def disconnect
      @consumer.close
    end
  end
end
