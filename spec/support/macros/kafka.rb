module KafkaMacro
  extend self

  def kafka_up!
    if Promiscuous::Kafka.backend.respond_to?(:orig_publish)
      Promiscuous::Kafka.backend.class_eval { alias_method :publish, :orig_publish }
    end
  end

  def kafka_down!
    prepare

    Promiscuous::Kafka.backend.class_eval { def publish(*args); raise RuntimeError.new("kafka DOWN!!!"); end }
  end

  def kafka_delayed!
    prepare

    Promiscuous::Kafka.backend.class_eval do
      cattr_accessor :delayed
      self.delayed = []

      def publish(*args)
        self.delayed << args
      end
    end
  end

  def kafka_process_delayed!
    Promiscuous::Kafka.backend.delayed.each { |args| Promiscuous::Kafka.backend.publish(*args) }
  end

  private

  def prepare
    Promiscuous::Kafka.backend.class_eval { alias_method :orig_publish, :publish }
  end
end

RSpec.configure do |config|
  config.after do
    KafkaMacro.kafka_up!
  end

  config.include KafkaMacro
end
