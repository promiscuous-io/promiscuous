module AMQPHelper
  def use_real_amqp(options={})
    Replicable::AMQP.configure({:backend => :rubyamqp, :app => 'sniper',
                                :queue_options => {:auto_delete => true}}.merge(options))
    Replicable::AMQP.logger.level = options[:logger_level] if options[:logger_level]
  end

  def use_fake_amqp(options={})
    Replicable::AMQP.configure({:backend => :fake, :app => 'crowdtap'}.merge(options))
  end
end
