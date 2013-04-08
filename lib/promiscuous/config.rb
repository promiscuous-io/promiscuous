module Promiscuous::Config
  mattr_accessor :app, :bootstrap, :bootstrap_chunk_size, :backend, :amqp_url,
                 :publisher_amqp_url, :subscriber_amqp_url, :publisher_exchange,
                 :subscriber_exchange, :queue_name, :queue_options, :redis_url,
                 :redis_urls, :redis_stats_url, :stats_interval,
                 :socket_timeout, :heartbeat, :bareback, :hash_size, :recovery,
                 :prefetch, :recovery_timeout, :logger, :subscriber_threads,
                 :error_notifier, :strict_multi_read

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

  def self._configure(&block)
    block.call(self) if block

    self.app                  ||= Rails.application.class.parent_name.underscore rescue nil if defined?(Rails)
    self.bootstrap            ||= false
    self.bootstrap_chunk_size ||= 10000
    self.backend              ||= best_amqp_backend
    self.amqp_url             ||= 'amqp://guest:guest@localhost:5672'
    self.publisher_amqp_url   ||= self.amqp_url
    self.subscriber_amqp_url  ||= self.amqp_url
    self.publisher_exchange   ||= Promiscuous::AMQP::LIVE_EXCHANGE
    self.subscriber_exchange  ||= Promiscuous::AMQP::LIVE_EXCHANGE
    self.queue_name           ||= "#{self.app}.promiscuous"
    self.queue_options        ||= {:durable => true, :arguments => {'x-ha-policy' => 'all'}}
    self.redis_url            ||= 'redis://localhost/'
    self.redis_urls           ||= [self.redis_url]
    # TODO self.redis_slave_url ||= nil
    self.redis_stats_url      ||= self.redis_urls.first
    self.stats_interval       ||= 0
    self.socket_timeout       ||= 10
    self.heartbeat            ||= 60
    self.bareback             ||= false
    self.hash_size            ||= 2**20 # one million keys ~ 200Mb.
    self.recovery             ||= false
    self.prefetch             ||= 1000
    self.recovery_timeout     ||= 10
    self.logger               ||= defined?(Rails) ? Rails.logger : Logger.new(STDERR).tap { |l| l.level = Logger::WARN }
    self.subscriber_threads   ||= 10
    self.error_notifier       ||= proc {}
    self.strict_multi_read    = true if self.strict_multi_read.nil?
  end

  def self.configure(&block)
    Promiscuous.disconnect

    self._configure(&block)

    unless self.app
      raise "Promiscuous.configure: please give a name to your app with \"config.app = 'your_app_name'\""
    end

    Promiscuous.connect

    hook_fork
  end

  def self.hook_fork
    return if @fork_hooked

    Kernel.module_eval do
      alias_method :fork_without_promiscuous, :fork

      def fork(&block)
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
end
