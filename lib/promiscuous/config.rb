module Promiscuous::Config
  mattr_accessor :app, :logger, :error_notifier, :backend, :amqp_url,
                 :redis_url, :stats_redis_url, :stats_interval,
                 :zookeeper_hosts, :queue_options, :heartbeat, :bareback,
                 :recovery, :prefetch, :use_transactions

  def self.backend=(value)
    @@backend = value
    Promiscuous::AMQP.backend = value
  end

  def self.reset
    Promiscuous::AMQP.backend = nil
    class_variables.each { |var| class_variable_set(var, nil) }
  end

  def self.transaction_safety_level=(value)
    value = value.to_sym
    possible_values = [:track_all, :track_all_writes, :track_published_writes]
    raise "Please use something in #{possible_values} (you gave :#{value})" unless value.in? possible_values
    @@transaction_safety_level = value
  end

  def self.configure(&block)
    block.call(self) if block

    self.app             ||= Rails.application.class.parent_name.underscore rescue nil if defined?(Rails)
    self.amqp_url        ||= 'amqp://guest:guest@localhost:5672'
    self.redis_url       ||= 'redis://localhost/'
    self.stats_redis_url ||= self.redis_url
    self.stats_interval  ||= 0
    self.zookeeper_hosts ||= nil
    self.backend         ||= RUBY_PLATFORM == 'java' ? :hot_bunny : :rubyamqp
    self.queue_options   ||= {:durable => true, :arguments => {'x-ha-policy' => 'all'}}
    self.heartbeat       ||= 60
    self.bareback        ||= false
    self.recovery        ||= false
    self.prefetch        ||= 1000
    self.logger          ||= defined?(Rails) ? Rails.logger : Logger.new(STDERR).tap { |l| l.level = Logger::WARN }
    self.use_transactions = true if self.use_transactions.nil?

    unless self.app
      raise "Promiscuous.configure: please give a name to your app with \"config.app = 'your_app_name'\""
    end

    # amqp connection is done in when setting the backend
    Promiscuous::Redis.connect
    Promiscuous::ZK.connect

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
