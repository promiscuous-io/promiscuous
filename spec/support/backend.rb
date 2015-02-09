module BackendHelper
  def reconfigure_backend(&block)
    Promiscuous.configure do |config|
      config.reset
      config.amqp_url = amqp_url
      config.app = 'test'
      config.redis_url = redis_url
      config.queue_options = {:auto_delete => true}
      config.logger = Logger.new(STDERR); STDERR.sync = true
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
    real_backends = [:both, :bunny, :poseidon]
    if !real_backends.include?(Promiscuous::Config.backend) || block
      reconfigure_backend do |config|
        config.backend = (ENV['BACKEND'])? ENV['BACKEND'].to_sym : :poseidon
        Promiscuous::Config.error_notifier = options[:error_notifier] if options[:error_notifier]
        block.call(config) if block
      end
    end

    Promiscuous.ensure_connected
    Promiscuous::Redis.connection.flushdb # not the ideal place to put it, deal with it.

    send("#{Promiscuous::Config.backend}_after_use_real_backend")
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
end

RSpec.configure do |config|
  config.after do
    [@recovery_worker, @worker].compact.each do |worker|
      worker.stop
      worker = nil
    end
  end
end
