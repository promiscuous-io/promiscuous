module Promiscuous::Kafka
  extend Promiscuous::Autoload
  autoload :Poseidon, :Null, :Fake, :File

  class << self
    attr_accessor :backend
    attr_accessor :backend_class

    def backend=(value)
      disconnect
      @backend_class = value.nil? ? nil : "Promiscuous::Kafka::#{value.to_s.camelize.gsub(/kafka/, 'Kafka')}".constantize
    end

    def lost_connection_exception(options={})
      Promiscuous::Error::Connection.new(Promiscuous::Config.kafka_url, options)
    end

    def ensure_connected
      Promiscuous.ensure_connected

      raise lost_connection_exception unless connected?
    end

    def connect
      return if @backend
      @backend = backend_class.new
      @backend.connect
    end

    def disconnect
      return unless @backend
      @backend.disconnect
      @backend.terminate if @backend.respond_to?(:terminate)
      @backend = nil
    end

    def new_connection(*args)
      ensure_connected
      backend.new_connection(*args)
    end

    delegate :publish, :connected?, :to => :backend

    def const_missing(sym)
      backend_class.const_get(sym)
    end
  end
end
