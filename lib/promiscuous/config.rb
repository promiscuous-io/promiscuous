module Promiscuous
  module Config
    mattr_accessor :app, :logger, :error_handler, :backend, :server_uri, :queue_options

    def self.backend=(value)
      @@backend = "Promiscuous::AMQP::#{value.to_s.camelize.gsub(/amqp/, 'AMQP')}".constantize
    end

    def self.configure(&block)
      class_variables.each { |var| class_variable_set(var, nil) }

      block.call(self)
      self.backend ||= defined?(EventMachine) && EventMachine.reactor_running? ? :rubyamqp : :bunny
      self.logger ||= defined?(Rails) ? Rails.logger : Logger.new(STDERR).tap { |l| l.level = Logger::WARN }
      self.queue_options ||= {:durable => true, :arguments => {'x-ha-policy' => 'all'}}

      Promiscuous::AMQP.connect
    end
  end
end
