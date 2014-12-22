module AMQPMacro
  extend self

  def amqp_up!
    if Promiscuous::AMQP.backend.respond_to?(:orig_publish)
      Promiscuous::AMQP.backend.class_eval { alias_method :publish, :orig_publish }
    end
  end

  def amqp_down!
    prepare

    Promiscuous::AMQP.backend.class_eval { def publish(*args); raise RuntimeError.new("amqp DOWN!!!"); end }
  end

  def amqp_delayed!
    prepare

    Promiscuous::AMQP.backend.class_eval do
      cattr_accessor :delayed
      self.delayed = []

      def publish(*args)
        self.delayed << args
      end
    end
  end

  def amqp_process_delayed!
    Promiscuous::AMQP.backend.delayed.each { |args| Promiscuous::AMQP.backend.publish(*args) }
  end

  def amqp_slow!(delay)
    prepare

    Promiscuous::AMQP.backend.class_eval do
      def publish(*args)
        sleep delay
        orig_publish(*args)
      end
    end
  end

  private

  def prepare
    Promiscuous::AMQP.backend.class_eval { alias_method :orig_publish, :publish }
  end
end

RSpec.configure do |config|
  config.after do
    AMQPMacro.amqp_up!
  end

  config.include AMQPMacro
end
