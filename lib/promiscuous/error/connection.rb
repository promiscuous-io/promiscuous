class Promiscuous::Error::Connection < Promiscuous::Error::Base
  attr_accessor :service, :url

  def initialize(options={})
    super(nil)
    self.service = options[:service]
    self.url = case service
    when :zookeeper then "zookeeper://#{Promiscuous::Config.zookeeper_hosts}"
    when :redis     then Promiscuous::Config.redis_url
    when :amqp      then Promiscuous::Config.amqp_url
    end
  end

  def message
    "Lost connection with #{url}"
  end

  alias to_s message
end
