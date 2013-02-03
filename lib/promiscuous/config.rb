module Promiscuous::Config
  mattr_accessor :app, :logger, :error_notifier, :backend, :amqp_url, :redis_url, :queue_options, :heartbeat

  def self.backend=(value)
    @@backend = value
    Promiscuous::AMQP.backend = value unless value.nil?
  end

  def self.configure(&block)
    class_variables.each { |var| class_variable_set(var, nil) }

    block.call(self)

    self.backend ||= defined?(EventMachine) && EventMachine.reactor_running? ? :rubyamqp : :bunny
    self.logger ||= defined?(Rails) ? Rails.logger : Logger.new(STDERR).tap { |l| l.level = Logger::WARN }
    self.queue_options ||= {:durable => true, :arguments => {'x-ha-policy' => 'all'}}
    self.heartbeat ||= 60

    Promiscuous.connect
  end
end
