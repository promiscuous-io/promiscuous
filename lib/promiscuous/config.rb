module Promiscuous
  module Config
    mattr_accessor :app, :logger, :error_notifier, :backend, :server_uri, :queue_options

    def self.backend=(value)
      @@backend = "Promiscuous::AMQP::#{value.to_s.camelize.gsub(/amqp/, 'AMQP')}".constantize unless value.nil?
    end

    def self.configure(&block)
      class_variables.each { |var| class_variable_set(var, nil) }

      block.call(self)

      self.backend ||= defined?(EventMachine) && EventMachine.reactor_running? ? :rubyamqp : :bunny
      self.logger ||= defined?(Rails) ? Rails.logger : Logger.new(STDERR).tap { |l| l.level = Logger::WARN }
      self.queue_options ||= {:durable => true, :arguments => {'x-ha-policy' => 'all'}}

      Promiscuous::AMQP.connect
    end

    # TODO backward compatibility. to be removed.
    def self.error_handler=(value)
      ActiveSupport::Deprecation.behavior = :stderr
      ActiveSupport::Deprecation.warn "'error_handler' is deprecated, please use 'error_notifier'", caller
      self.error_notifier = value
    end
  end
end
