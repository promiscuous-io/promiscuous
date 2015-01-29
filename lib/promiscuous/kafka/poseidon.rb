require 'poseidon'
require 'poseidon_cluster'

class Promiscuous::Kafka::Poseidon

  # TODO: Move to spec support
  def self.advance_offsets_forward!
    broker_pool = ::Poseidon::BrokerPool.new(::Poseidon::Cluster.guid,
                                             Promiscuous::Config.kafka_hosts,
                                             Promiscuous::Config.socket_timeout)

    broker_host, broker_port = Promiscuous::Config.kafka_hosts.first.split(':')
    broker_pool.update_known_brokers({ 0 => { :host => broker_host, :port => broker_port }})

    # we assume that a topic maps to a ConsumerGroup one-to-one
    zk = ZK.new(Promiscuous::Config.zookeeper_hosts.join(','))
    begin
      Promiscuous::Config.subscriber_topics.each do |topic|
        partitions_path = "/consumers/#{topic}/offsets/#{topic}"
        zk.children(partitions_path).each do |partition|
          partition_offset_requests = [::Poseidon::Protocol::PartitionOffsetRequest.new(partition.to_i, -1, 1000)]
          offset_topic_requests = [::Poseidon::Protocol::TopicOffsetRequest.new(topic, partition_offset_requests)]
          offset_responses = broker_pool.execute_api_call(0, :offset, offset_topic_requests)
          latest_offset = offset_responses.first.partition_offsets.first.offsets.first.offset

          zk.set([ partitions_path, partition ].join('/'), latest_offset.to_s)
        end
      end
    rescue ZK::Exceptions::NoNode
      # It's ok. Nothing to advance.
    end
    zk.close
    broker_pool.close

    true
  end

  attr_accessor :connection, :connection_lock

  def initialize
    # The poseidon socket doesn't like when multiple threads access to it apparently
    @connection_lock = Mutex.new
  end

  def new_connection
    # TODO: client id needs to be unique across the system, use hostname+rand?
    client_id = ['promiscuous', Promiscuous::Config.app, Poseidon::Cluster.guid].join('.')
    connection = ::Poseidon::Producer.new(Promiscuous::Config.kafka_hosts, client_id,
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
    # Poseidon.logger = Logger.new(STDOUT).tap { |l| l.level = 0 }
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
    ok = false
    10.times do
      ok = @connection.send_messages([Poseidon::MessageToSend.new(options[:topic], options[:payload], options[:key])])
      break if ok
      sleep(1)
    end
    raise "Unable to send messages" if !ok
  end

  def publish(options={})
    @connection_lock.synchronize do
      raw_publish(options)
      options[:on_confirm].call if options[:on_confirm]
      Promiscuous.debug "[publish] [kafka] #{options[:topic]}/#{options[:topic_key]} #{options[:payload]}"
    end
  rescue Exception => e
    Promiscuous.warn("[publish] Failure publishing to kafka #{e}\n#{e.backtrace.join("\n")}")
    e = Promiscuous::Error::Publisher.new(e, :payload => options[:payload])

    if options[:async]
      Promiscuous::Config.error_notifier.call(e)
    else
      raise e
    end
  end

  module Subscriber
    def subscribe(topic)
      @consumer = ::Poseidon::ConsumerGroup.new(Promiscuous::Config.app,
                                                Promiscuous::Config.kafka_hosts,
                                                Promiscuous::Config.zookeeper_hosts,
                                                topic, :trail => Promiscuous::Config.test_mode, :max_wait_ms => 10)
    end

    def fetch_and_process_messages(&block)
      Promiscuous.debug "[kafka] Fetching messages topic:#{@consumer.topic} #{Thread.current}"
      payload_count = 0
      fetched_messages = @consumer.fetch(:commit => false) do |partition, payloads|
        payload_count = payloads.count
        Promiscuous.debug "[kafka] Received #{payload_count} payloads topic:#{@consumer.topic} #{Thread.current}"
        payloads.each do |payload|
          Promiscuous.debug "[kafka] Fetched '#{payload.value}' topic:#{@consumer.topic} offset:#{payload.offset} parition:#{partition}"
          block.call(MetaData.new(@consumer, partition, payload.offset), payload)
        end
      end

      if !fetched_messages || payload_count == 0
        sleep 0.1
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
