module AMQPHelper
  def use_real_amqp(options={})
    Replicable::AMQP.configure({:backend => :rubyamqp, :app => 'test_subscriber',
                                :queue_options => {:auto_delete => true}}.merge(options))
    Replicable::AMQP.logger.level = ENV["LOGGER_LEVEL"].to_i if ENV["LOGGER_LEVEL"]
    Replicable::AMQP.logger.level = options[:logger_level] if options[:logger_level]
  end

  def use_fake_amqp(options={})
    Replicable::AMQP.configure({:backend => :fake, :app => 'test_publisher'}.merge(options))
  end
end
