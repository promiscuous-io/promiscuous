require 'poseidon'
require 'poseidon_cluster'

class Promiscuous::Backend::Poseidon
  attr_accessor :connection, :connection_lock

  def initialize
    # The poseidon socket doesn't like when multiple threads access to it apparently
    @connection_lock = Mutex.new
  end

  def new_connection
    client_id = ['promiscuous', Promiscuous::Config.app, Poseidon::Cluster.guid].join('.')
    @connection = ::Poseidon::Producer.new(Promiscuous::Config.kafka_hosts, client_id,
                                          :type => :sync,
                                          :compression_codec => :none,
                                          :metadata_refresh_interval_ms => 600_000,
                                          :max_send_retries => 10,
                                          :retry_backoff_ms => 100,
                                          :required_acks => 1,
                                          :ack_timeout_ms => 1000,
                                          :socket_timeout_ms => Promiscuous::Config.socket_timeout)
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

  # TODO: extend Poseidon with a connected? method
  def connected?
    @connection.present?
  end

  def raw_publish(options)
    if @connection.send_messages([Poseidon::MessageToSend.new(options[:topic], options[:payload], options[:topic_key])])
      Promiscuous.debug "[publish] [kafka] #{options[:topic]}/#{options[:topic_key]} #{options[:payload]}"
    else
      raise Promiscuous::Error::Publisher.new(Exception.new('Unable to send message'), :payload => options[:payload])
    end
  rescue Poseidon::Errors::UnableToFetchMetadata
    Promiscuous.error "[publish] [kafka] Unable to fetch metatdata from the cluster"
  end

  def publish(options={})
    @connection_lock.synchronize do
      raw_publish(options)
      options[:on_confirm].call if options[:on_confirm] && Promiscuous::Config.backend == :poseidon
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

  def process_message(message)
    retries = 0
    retry_max = 50

    begin
      Promiscuous::Subscriber::UnitOfWork.process(message)
    rescue Exception => e
      Promiscuous::Config.error_notifier.call(e)
      raise e if Promiscuous::Config.test_mode

      if retries < retry_max
        retries += 1
        sleep Promiscuous::Config.error_ttl / 1000.0
        retry
      end
    end
  end

  module Subscriber
    def subscribe(options)
      raise "No topic specified" unless options[:topic]

      @consumer = ::Poseidon::ConsumerGroup.new(Promiscuous::Config.app,
                                                Promiscuous::Config.kafka_hosts,
                                                Promiscuous::Config.zookeeper_hosts,
                                                options[:topic], :trail => Promiscuous::Config.test_mode, :max_wait_ms => 10)
    end

    def fetch_and_process_messages(&block)
      @consumer.fetch(:commit => false) do |partition, payloads|
        payloads.each do |payload|
          Promiscuous.debug "[kafka] [receive] #{payload.value} topic:#{@consumer.topic} offset:#{payload.offset} parition:#{partition} #{Thread.current.object_id}"
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

    module Worker
      def backend_subscriber_initialize(subscriber_worker)
        @distributor = Promiscuous::Subscriber::Worker::Distributor.new(subscriber_worker)
      end

      def backend_subscriber_start
        @distributor.start
      end

      def backend_subscriber_stop
        @distributor.stop
      end

      def backend_subscriber_show_stop_status(num_show_stop_requests)
        @distributor.show_stop_status(num_show_stop_requests)
      end
    end

    def disconnect
      @consumer.close
    end
  end
end
