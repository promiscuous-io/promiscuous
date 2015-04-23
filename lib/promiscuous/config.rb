module Promiscuous::Config
  mattr_accessor :app, :backend, :amqp_url,
                 :publisher_amqp_url, :subscriber_amqp_url, :publisher_exchange,
                 :subscriber_exchanges, :sync_exchange, :queue_name, :queue_options,
                 :redis_url, :redis_stats_url, :stats_interval, :error_queue_name,
                 :socket_timeout, :heartbeat, :sync_all_routing, :rabbit_mgmt_url,
                 :prefetch, :recovery_timeout, :recovery_interval, :logger, :subscriber_threads,
                 :version_field, :error_notifier, :transport_collection, :queue_policy, :test_mode,
                 :on_stats, :max_retries, :generation, :destroy_timeout, :destroy_check_interval,
                 :error_exchange, :error_routing, :retry_routing, :error_ttl, :transport_persistence

  def self.backend=(value)
    @@backend = value
    Promiscuous::AMQP.backend = value
  end

  def self.reset
    Promiscuous::AMQP.backend = nil
    class_variables.each { |var| class_variable_set(var, nil) }
  end

  def self.best_amqp_backend
    if RUBY_PLATFORM == 'java'
      begin
        require 'hot_bunnies'
        :hot_bunnies
      rescue LoadError
        :bunny
      end
    else
      :bunny
    end
  end

  def self.best_transport_persistence
    if defined?(Mongoid::Document)
      self.transport_persistence = :mongoid
    elsif defined?(ActiveRecord::Base)
      self.transport_persistence = :active_record
    end
  end

  def self._configure(&block)
    block.call(self) if block

    self.app                  ||= Rails.application.class.parent_name.underscore rescue nil if defined?(Rails)
    self.backend              ||= best_amqp_backend
    self.amqp_url             ||= 'amqp://guest:guest@localhost:5672'
    self.rabbit_mgmt_url      ||= 'http://guest:guest@localhost:15672'
    self.publisher_amqp_url   ||= self.amqp_url
    self.subscriber_amqp_url  ||= self.amqp_url
    self.publisher_exchange   ||= 'promiscuous'
    self.sync_exchange        ||= 'promiscuous.sync'
    #self.sync_exchange        ||= 'promiscuous'
    self.subscriber_exchanges ||= [self.publisher_exchange]
    self.sync_all_routing     ||= :__all__
    self.queue_name           ||= "#{self.app}.subscriber"
    self.error_exchange       ||= "#{self.app}.error"
    self.error_queue_name     ||= "#{self.app}.error"
    self.error_routing        ||= :__error__
    self.retry_routing        ||= :__retry__
    self.error_ttl            ||= 30000
    self.queue_policy         ||= { 'ha-mode' => 'all' }
    self.queue_options        ||= { :durable => true }
    self.redis_url            ||= 'redis://localhost/'
    # TODO self.redis_slave_url ||= nil
    self.redis_stats_url      ||= self.redis_url
    self.stats_interval       ||= 0
    self.socket_timeout       ||= 10
    self.heartbeat            ||= 60
    self.prefetch             ||= 1000
    self.recovery_timeout     ||= 10.seconds
    self.recovery_interval    ||= 5.seconds
    self.logger               ||= defined?(Rails) ? Rails.logger : Logger.new(STDERR).tap { |l| l.level = Logger::WARN }
    self.subscriber_threads   ||= 10
    self.error_notifier       ||= proc {}
    self.version_field        ||= '_v'
    self.transport_collection ||= '_promiscuous'
    self.on_stats             ||= proc { |rate, latency| }
    self.max_retries          ||= defined?(Rails) ? Rails.env.production? ? 10 : 0 : 10
    self.generation           ||= 0
    self.destroy_timeout      ||= 1.hour
    self.destroy_check_interval ||= 10.minutes
    self.transport_persistence ||= best_transport_persistence
    self.test_mode            = set_test_mode
  end

  def self.set_test_mode
    if self.test_mode.nil?
      defined?(Rails) ? Rails.env.test? ? true : false : false
    else
      self.test_mode
    end
  end

  def self.configure(&block)
    reconnect_if_connected do
      self._configure(&block)

      unless self.app
        raise "Promiscuous.configure: please give a name to your app with \"config.app = 'your_app_name'\""
      end
    end

    hook_fork
  end

  def self.hook_fork
    return if @fork_hooked

    Kernel.module_eval do
      alias_method :fork_without_promiscuous, :fork

      def fork(&block)
        return fork_without_promiscuous(&block) unless Promiscuous.should_be_connected?

        Promiscuous.disconnect
        pid = if block
          fork_without_promiscuous do
            Promiscuous.connect
            block.call
          end
        else
          fork_without_promiscuous
        end
        Promiscuous.connect
        pid
      rescue Exception => e
        puts e
        puts e.backtrace.join("\n")
        raise e
      end

      module_function :fork
    end

    @fork_hooked = true
  end

  def self.configured?
    self.app != nil
  end

  private

  def self.reconnect_if_connected(&block)
    if Promiscuous.should_be_connected?
      Promiscuous.disconnect
      yield
      Promiscuous.connect
    else
      yield
    end
  end
end
