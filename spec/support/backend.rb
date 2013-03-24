module BackendHelper
  def use_real_backend(options={})
    real_backend = RUBY_PLATFORM == 'java' ? :hot_bunny : :bunny
    if Promiscuous::Config.backend != real_backend
      Promiscuous.configure do |config|
        config.reset
        config.redis_urls = 8.times.map { |i| "redis://localhost/#{i}" }
        config.backend = real_backend
        config.app = options[:app] || 'test_subscriber'
        config.queue_options = {:auto_delete => true}
      end
    end
    Promiscuous::Config.error_notifier = options[:error_notifier] if options[:error_notifier]

    Promiscuous::Redis.master.flushdb # not the ideal place to put it, deal with it.

    config_logger(options)
  end

  def run_subscriber_worker!
    @worker.terminate if @worker
    @worker = Promiscuous::Subscriber::Worker.run!
    Celluloid::Actor[:pump].wait_for_subscription
  end

  def use_null_backend(options={})
    Promiscuous.configure do |config|
      config.reset
      config.backend = :null
      config.app = options[:app] || 'test_publisher'
    end
    config_logger(options)
  end

  def use_fake_backend(options={})
    Promiscuous.configure do |config|
      config.reset
      config.redis_urls = 8.times.map { |i| "redis://localhost/#{i}" }
      config.backend = :fake
      config.app = options[:app] || 'test_publisher'
    end
    Promiscuous::Redis.master.flushdb # not the ideal place to put it, deal with it.
    config_logger(options)
  end

  def config_logger(options={})
    Promiscuous::Config.logger.level = ENV["LOGGER_LEVEL"].to_i if ENV["LOGGER_LEVEL"]
    Promiscuous::Config.logger.level = options[:logger_level] if options[:logger_level]
    Promiscuous::Config.stats_interval = 0
  end
end

RSpec.configure do |config|
  config.after do
    if @worker
      @worker.terminate
      @worker = nil
    end
  end
end
