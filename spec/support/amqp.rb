module AMQPHelper
  def use_real_amqp(options={})
    Promiscuous::AMQP.configure({:backend => :rubyamqp, :app => 'test_subscriber',
                                :queue_options => {:auto_delete => true}}.merge(options))
    Promiscuous::AMQP.logger.level = ENV["LOGGER_LEVEL"].to_i if ENV["LOGGER_LEVEL"]
    Promiscuous::AMQP.logger.level = options[:logger_level] if options[:logger_level]
  end

  def use_fake_amqp(options={})
    Promiscuous::AMQP.configure({:backend => :fake, :app => 'test_publisher'}.merge(options))
  end
end
