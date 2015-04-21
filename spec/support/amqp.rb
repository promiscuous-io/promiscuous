module AMQPHelper
  def bunny_after_use_real_backend
    [Promiscuous::Config.queue_name, Promiscuous::Config.error_queue_name].each do |queue|
      Promiscuous::Rabbit::Policy.delete(queue)
    end
  end

  def amqp_url
    ENV['BOXEN_RABBITMQ_URL'] || 'amqp://guest:guest@localhost:5672'
  end

  def rabbit_mgmt_url
    ENV['BOXEN_RABBITMQ_MGMT_URL'] || 'http://guest:guest@localhost:15672'
  end
end

RSpec.configure do |config|
end
