module KafkaHelper
  def advance_offsets_forward!
    broker_pool = ::Poseidon::BrokerPool.new(::Poseidon::Cluster.guid,
                                             Promiscuous::Config.kafka_hosts,
                                             Promiscuous::Config.socket_timeout)

    broker_host, broker_port = Promiscuous::Config.kafka_hosts.first.split(':')
    broker_pool.update_known_brokers({ 0 => { :host => broker_host, :port => broker_port }})

    # we assume that a topic maps to a ConsumerGroup one-to-one
    zk = ZK.new(Promiscuous::Config.zookeeper_hosts.join(','))
    begin
      Promiscuous::Config.subscriber_topics.each do |topic|
        partitions_path = "/consumers/#{topic}:#{topic}/offsets/#{topic}"
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
    zk.close! # otherwise connections lay around
    broker_pool.close

    true
  end

  def poseidon_after_use_real_backend
    advance_offsets_forward!
  end

  def kafka_hosts
    ["localhost:#{TestCluster::KAFKA_PORT}"]
  end

  def zookeeper_hosts
    ["localhost:#{TestCluster::ZOOKP_PORT}"]
  end
end

if ENV['POSEIDON_LOGGER_LEVEL']
  require 'poseidon'
  Poseidon.logger = Logger.new(STDOUT).tap { |l| l.level = ENV['POSEIDON_LOGGER_LEVEL'].to_i }
end

if ENV['BACKEND'] != 'bunny'
  RSpec.configure do |config|
    config.before(:suite) do
      $tc ||= TestCluster.new
      $tc.start
    end

    config.after(:suite) do
      $tc.stop
    end
  end
end
