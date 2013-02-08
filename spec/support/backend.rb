module BackendHelper
  def use_real_backend(options={})
    if Promiscuous::Config.backend != :rubyamqp
      Promiscuous.configure do |config|
        config.reset
        config.backend = :rubyamqp
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
    Celluloid::Actor[:pump].subscribe_sync.wait
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
