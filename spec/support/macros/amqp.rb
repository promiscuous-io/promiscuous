module AMQPMacro
  extend self

  def amqp_up!
    if Promiscuous::AMQP.backend.respond_to?(:orig_raw_publish)
      Promiscuous::AMQP.backend.class_eval { alias_method :raw_publish, :orig_raw_publish }
    end
  end

  def amqp_down!
    prepare

    Promiscuous::AMQP.backend.class_eval { def raw_publish(*args); raise RuntimeError.new("amqp DOWN!!!"); end }
  end

  def amqp_delayed!
    prepare

    Promiscuous::AMQP.backend.class_eval do
      cattr_accessor :delayed
      self.delayed = []

      def raw_publish(*args)
        self.delayed << args
      end
    end
  end

  def amqp_process_delayed!
    Promiscuous::AMQP.backend.delayed.each { |args| Promiscuous::AMQP.backend.raw_publish(*args) }
  end

  private

  def prepare
    Promiscuous::AMQP.backend.class_eval { alias_method :orig_raw_publish, :raw_publish }
  end
end

RSpec.configure do |config|
  config.after do
    AMQPMacro.amqp_up!
  end

  config.include AMQPMacro
end
