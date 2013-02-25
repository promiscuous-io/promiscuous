module Promiscuous::Config
  mattr_accessor :app, :logger, :error_notifier, :backend, :amqp_url,
                 :redis_url, :zookeeper_hosts, :queue_options, :heartbeat, :bareback,
                 :recovery, :prefetch, :use_transactions, :transaction_forget_rate,
                 :transaction_safety_level

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
    self.zookeeper_hosts ||= nil
    self.backend         ||= RUBY_PLATFORM == 'java' ? :hot_bunny : :rubyamqp
    self.queue_options   ||= {:durable => true, :arguments => {'x-ha-policy' => 'all'}}
    self.heartbeat       ||= 60
    self.bareback        ||= false
    self.recovery        ||= false
    self.prefetch        ||= 1000
    self.logger          ||= defined?(Rails) ? Rails.logger : Logger.new(STDERR).tap { |l| l.level = Logger::WARN }

    self.use_transactions = true if self.use_transactions.nil?
    self.transaction_forget_rate  ||= 10
    self.transaction_safety_level ||= :track_all_writes # can be :track_published_writes, :track_all

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
        pid = fork_without_promiscuous do
          Promiscuous.connect
          block.call if block
        end
        Promiscuous.connect if pid
        pid
      end
    end

    @fork_hooked = true
  end

  def self.configured?
    self.app != nil
  end
end
