module BackendHelper
  def use_real_backend(options={})
    Promiscuous.configure do |config|
      config.reset
      config.app = options[:app] || 'test_subscriber'
      config.queue_options = {:auto_delete => true}
      config.error_notifier = options[:error_notifier] if options[:error_notifier]
    end
    Promiscuous::Redis.master.flushdb # not the ideal place to put it, deal with it.

    config_logger(options)
  end

  def run_subscriber_worker!
    @worker.terminate if @worker
    @worker = Promiscuous::Subscriber::Worker.run!
    sleep 0.1 # let amqp connect, otherwise it can say "Connection Lost" when trying to publish
  end

  def use_null_backend(options={})
    Promiscuous.configure do |config|
      config.reset
      config.backend = :null
      config.app = options[:app] || 'test_publisher'
    end
    config_logger(options)
  end

  def config_logger(options={})
    Promiscuous::Config.logger.level = ENV["LOGGER_LEVEL"].to_i if ENV["LOGGER_LEVEL"]
    Promiscuous::Config.logger.level = options[:logger_level] if options[:logger_level]
  end
end

RSpec.configure do |config|
  config.after do
    @worker.terminate if @worker
    @worker = nil
  end
end
