require 'securerandom'

module BackendHelper
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

  def reconfigure_backend(&block)
    STDERR.sync = true

    Promiscuous.configure do |config|
      config.reset
      config.amqp_url = amqp_url
      config.app = 'test'
      config.redis_url = redis_url
      config.queue_options = {:auto_delete => true}
      config.logger = Logger.new(STDERR)
      config.logger.level = ENV["LOGGER_LEVEL"] ? ENV["LOGGER_LEVEL"].to_i : Logger::ERROR
      config.stats_interval = 0
      config.destroy_timeout = 0
      config.destroy_check_interval = 0
      config.max_retries = 0
      config.rabbit_mgmt_url = rabbit_mgmt_url
      # config.kafka_hosts = kafka_hosts
      # config.zookeeper_hosts = zookeeper_hosts
      block.call(config) if block
    end
    Promiscuous.connect
  end

  def use_real_backend(options={}, &block)
    real_backend = RUBY_PLATFORM == 'java' ? :hot_bunnies : :bunny
    if Promiscuous::Config.backend != real_backend || block
      reconfigure_backend do |config|
        config.backend = real_backend
        Promiscuous::Config.error_notifier = options[:error_notifier] if options[:error_notifier]
        block.call(config) if block
      end
    end
    advance_offsets_forward!
    Promiscuous.ensure_connected
    Promiscuous::Redis.connection.flushdb # not the ideal place to put it, deal with it.
    [Promiscuous::Config.queue_name, Promiscuous::Config.error_queue_name].each { |queue| Promiscuous::Rabbit::Policy.delete(queue) }

  end

  def run_subscriber_worker!
    @worker.stop if @worker
    @worker = Promiscuous::Subscriber::Worker.new
    @worker.start
  end

  def run_recovery_worker!
    @recovery_worker.stop if @recovery_worker
    @recovery_worker = Promiscuous::Publisher::Worker.new
    @recovery_worker.start
  end

  def use_null_backend(&block)
    reconfigure_backend do |config|
      config.backend = :null
      block.call(config) if block
    end
  end

  def use_fake_backend(&block)
    reconfigure_backend do |config|
      config.backend = :fake
      block.call(config) if block
    end
    Promiscuous::Redis.connection.flushdb # not the ideal place to put it, deal with it
  end

  private

  def redis_url
    ENV["BOXEN_REDIS_URL"] || "redis://localhost/"
  end

  def amqp_url
    ENV['BOXEN_RABBITMQ_URL'] || 'amqp://guest:guest@localhost:5672'
  end

  def rabbit_mgmt_url
    ENV['BOXEN_RABBITMQ_MGMT_URL'] || 'http://guest:guest@localhost:15672'
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

RSpec.configure do |config|
  # config.before do
    # $tc ||= TestCluster.new
    # $tc.start
  # end

  config.after do
    @worker.try { |worker| worker.pump.delete_queues }
    [@recovery_worker, @worker].compact.each do |worker|
      worker.stop
      worker = nil
    end

    # $tc.stop
  end
end
