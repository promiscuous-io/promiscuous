module Promiscuous::Config
  mattr_accessor :app, :backend, :kafka_backend, :kafka_hosts, :zookeeper_hosts, :publisher_topic,
                 :subscriber_topics, :redis_url, :redis_stats_url, :stats_interval,
                 :socket_timeout, :heartbeat, :sync_all_routing, :sync_topic, :prefetch,
                 :publisher_lock_expiration, :publisher_lock_timeout,
                 :recovery_interval, :logger, :subscriber_threads, :version_field,
                 :error_notifier, :test_mode, :on_stats, :max_retries, :generation,
                 :destroy_timeout, :destroy_check_interval, :error_retry_max, :error_ttl,
    # vvvv REMOVE AFTER AMQP IS GONE vvvv
                 :amqp_url, :publisher_amqp_url, :subscriber_amqp_url,
                 :publisher_exchange, :subscriber_exchanges, :sync_exchange, :queue_name,
                 :queue_options, :error_queue_name, :rabbit_mgmt_url, :queue_policy,
                 :error_exchange, :error_routing, :retry_routing

  def self.backend=(value)
    @@backend = value
    Promiscuous::Backend.driver = value
  end

  def self.reset
    Promiscuous::Backend.driver = nil
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

  def self._configure(&block)
    block.call(self) if block

    self.app                  ||= Rails.application.class.parent_name.underscore rescue nil if defined?(Rails)
    self.backend              ||= :poseidon
    self.kafka_hosts          ||= ['localhost:9092']
    self.zookeeper_hosts      ||= ['localhost:2181']
    self.publisher_topic      ||= self.app
    self.subscriber_topics    ||= [self.publisher_topic]
    self.sync_all_routing     ||= :__all__
    self.error_retry_max      ||= 10
    self.error_ttl            ||= 1000

    # vvvv REMOVE AFTER AMQP IS GONE vvvv
    self.amqp_url             ||= 'amqp://guest:guest@localhost:5672'
    self.rabbit_mgmt_url      ||= 'http://guest:guest@localhost:15672'
    self.publisher_amqp_url   ||= self.amqp_url
    self.subscriber_amqp_url  ||= self.amqp_url
    self.publisher_exchange   ||= 'promiscuous'
    self.sync_exchange        ||= 'promiscuous.sync'
    self.subscriber_exchanges ||= [self.publisher_exchange]
    self.queue_name           ||= "#{self.app}.subscriber"
    self.error_exchange       ||= "#{self.app}.error"
    self.error_queue_name     ||= "#{self.app}.error"
    self.error_routing        ||= :__error__
    self.retry_routing        ||= :__retry__
    self.queue_policy         ||= { 'ha-mode' => 'all' }
    self.queue_options        ||= { :durable => true }
    # ^^^^ REMOVE AFTER AMQP IS GONE ^^^^

    self.redis_url            ||= 'redis://localhost/'
    # TODO self.redis_slave_url ||= nil
    self.redis_stats_url      ||= self.redis_url
    self.stats_interval       ||= 0
    self.socket_timeout       ||= 50
    self.heartbeat            ||= 60
    self.prefetch             ||= 1000
    self.publisher_lock_expiration ||= 5.seconds
    self.publisher_lock_timeout ||= 2.seconds
    self.recovery_interval    ||= 5.seconds
    self.logger               ||= defined?(Rails) ? Rails.logger : Logger.new(STDERR).tap { |l| l.level = Logger::WARN }
    self.subscriber_threads   ||= 1
    self.error_notifier       ||= proc {}
    self.version_field        ||= '_v'
    self.on_stats             ||= proc { |rate, latency| }
    self.max_retries          ||= defined?(Rails) ? Rails.env.production? ? 10 : 0 : 10
    self.generation           ||= 0
    self.destroy_timeout      ||= 1.hour
    self.destroy_check_interval ||= 10.minutes
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

      # Automatically subscribe to our personal sync topic
      self.subscriber_topics << self.sync_topic(self.app)
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
      rescue StandardError => e
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

  def self.sync_topic(target)
    [target, 'sync'].join('.')
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
