module Promiscuous::Backend
  extend Promiscuous::Autoload
  autoload :Both, :Bunny, :Poseidon, :Null, :Fake, :File

  class << self
    attr_accessor :driver
    attr_accessor :driver_class
    attr_accessor :subscriber_class
    attr_accessor :subscriber_methods

    def driver=(value)
      disconnect
      @driver_class = value.try { |v| "Promiscuous::Backend::#{v.to_s.camelize.gsub(/backend/, 'Backend')}".constantize }
      @subscriber_class = @driver_class.try { |dc| "#{dc}::Subscriber".constantize rescue nil }
      @subscriber_methods = @subscriber_class.try { |sc| "#{sc}::Worker".constantize rescue nil }
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

    delegate :publish, :connected?, :process_message, :to => :driver

    def const_missing(sym)
      driver_class.const_get(sym)
    end
  end
end
