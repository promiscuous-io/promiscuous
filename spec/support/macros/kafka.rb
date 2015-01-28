module KafkaMacro
  extend self

  def kafka_up!
    if Promiscuous::Kafka.backend.respond_to?(:orig_raw_publish)
      Promiscuous::Kafka.backend.class_eval { alias_method :raw_publish, :orig_raw_publish }
    end
  end

  def kafka_down!
    prepare

    Promiscuous::Kafka.backend.class_eval { def raw_publish(*args); raise RuntimeError.new("kafka DOWN!!!"); end }
  end

  def kafka_delayed!
    prepare

    Promiscuous::Kafka.backend.class_eval do
      cattr_accessor :delayed
      self.delayed = []

      def raw_publish(*args)
        self.delayed << args
      end
    end
  end

  def kafka_process_delayed!
    Promiscuous::Kafka.backend.delayed.each { |args| Promiscuous::Kafka.backend.raw_publish(*args) }
    Promiscuous::Kafka.backend.delayed = []
  end

  private

  def prepare
    Promiscuous::Kafka.backend.class_eval { alias_method :orig_raw_publish, :raw_publish }
  end
end

RSpec.configure do |config|
  config.after do
    KafkaMacro.kafka_up!
  end

  config.include KafkaMacro
end
