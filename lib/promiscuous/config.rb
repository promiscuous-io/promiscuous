module Promiscuous::Config
  mattr_accessor :app, :logger, :error_notifier, :backend, :amqp_url,
                 :redis_url, :queue_options, :heartbeat, :bareback,
                 :recovery, :prefetch

  def self.backend=(value)
    @@backend = value
    Promiscuous::AMQP.backend = value
  end

  def self.reset
    Promiscuous::AMQP.backend = nil
    class_variables.each { |var| class_variable_set(var, nil) }
  end

  def self.configure(&block)
    block.call(self)

    self.app ||= Rails.application.class.parent_name.underscore rescue nil if defined?(Rails)
    unless self.app
      raise "Promiscuous.configure: please give a name to your app with \"config.app = 'your_app_name'\""
    end
    self.backend ||= :rubyamqp # amqp connection is done in Promiscuous::AMQP
    Promiscuous::Redis.connect
    self.logger ||= defined?(Rails) ? Rails.logger : Logger.new(STDERR).tap { |l| l.level = Logger::WARN }
    self.queue_options ||= {:durable => true, :arguments => {'x-ha-policy' => 'all'}}
    self.heartbeat ||= 60
    self.prefetch ||= 1000
  end

  def self.configured?
    self.app != nil
  end
end
