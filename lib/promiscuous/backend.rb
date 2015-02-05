module Promiscuous::Backend
  extend Promiscuous::Autoload
  autoload :Bunny, :Poseidon, :Null, :Fake, :File

  class << self
    attr_accessor :driver
    attr_accessor :driver_class
    attr_accessor :subscriber_worker_module

    def driver=(value)
      disconnect
      @driver_class = value.nil? ? nil : "Promiscuous::Backend::#{value.to_s.camelize.gsub(/backend/, 'Backend')}".constantize
      @subscriber_worker_module = @driver_class.nil? ? nil : "#{@driver_class}::Subscriber::Worker".constantize
    end

    def lost_connection_exception(options={})
      Promiscuous::Error::Connection.new(Promiscuous::Config.backend_url, options)
    end

    def ensure_connected
      Promiscuous.ensure_connected

      raise lost_connection_exception unless connected?
    end

    def connect
      return if @driver
      @driver = driver_class.new
      @driver.connect
    end

    def disconnect
      return unless @driver
      @driver.disconnect
      @driver.terminate if @driver.respond_to?(:terminate)
      @driver = nil
    end

    def new_connection(*args)
      ensure_connected
      driver.new_connection(*args)
    end

    delegate :publish, :connected?, :to => :driver

    def const_missing(sym)
      driver_class.const_get(sym)
    end
  end
end
