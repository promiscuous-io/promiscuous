module BackendHelper
  NUM_SHARDS = 8
  #HASH_SIZE = 2**30
  HASH_SIZE = 0

  def reconfigure_backend(&block)
    Promiscuous.configure do |config|
      config.reset
      config.redis_urls = NUM_SHARDS.times.map { |i| "redis://localhost/#{i}" }
      config.app = 'test'
      config.queue_options = {:auto_delete => true}
      config.hash_size = HASH_SIZE
      config.logger = Logger.new(STDERR)
      config.logger.level = ENV["LOGGER_LEVEL"] ? ENV["LOGGER_LEVEL"].to_i : Logger::WARN
      config.stats_interval = 0
      block.call(config) if block
    end
    Promiscuous.connect
  end

  def use_real_backend(options={}, &block)
    real_backend = RUBY_PLATFORM == 'java' ? :hot_bunnies : :bunny
    unless Promiscuous::Config.backend == real_backend
      reconfigure_backend do |config|
        config.backend = real_backend
        Promiscuous::Config.error_notifier = options[:error_notifier] if options[:error_notifier]
        block.call(config) if block
      end
    end
    Promiscuous.ensure_connected
    Promiscuous::Redis.master.flushdb # not the ideal place to put it, deal with it.
  end

  def run_subscriber_worker!
    @worker.stop if @worker
    @worker = Promiscuous::Subscriber::Worker.new
    @worker.start
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
    Promiscuous::Redis.master.flushdb # not the ideal place to put it, deal with it.
  end
end

RSpec.configure do |config|
  config.after do
    if @worker
      @worker.stop
      @worker = nil
    end
  end
end
