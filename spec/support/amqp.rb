module AMQPHelper
  def use_real_amqp(options={})
    Promiscuous.configure do |config|
      config.app = options[:app] || 'test_subscriber'
      config.queue_options = {:auto_delete => true}
      config.error_handler = options[:error_handler] if options[:error_handler]
    end
    config_logger(options)
  end

  def use_null_amqp(options={})
    Promiscuous.configure do |config|
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
