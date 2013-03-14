module Promiscuous::Config
  mattr_accessor :app, :logger, :error_notifier, :backend, :amqp_url,
                 :redis_url, :redis_slave_url, :redis_stats_url,
                 :stats_interval, :queue_options, :heartbeat, :bareback,
                 :hash_size, :recovery, :prefetch, :recovery_timeout

  def self.backend=(value)
    @@backend = value
    Promiscuous::AMQP.backend = value
  end

  def self.reset
    Promiscuous::AMQP.backend = nil
    class_variables.each { |var| class_variable_set(var, nil) }
  end

  def self.configure(&block)
    block.call(self) if block

    self.app              ||= Rails.application.class.parent_name.underscore rescue nil if defined?(Rails)
    self.amqp_url         ||= 'amqp://guest:guest@localhost:5672'
    self.redis_url        ||= 'redis://localhost/'
    self.redis_slave_url  ||= nil
    self.redis_stats_url  ||= self.redis_url
    self.stats_interval   ||= 0
    self.backend          ||= RUBY_PLATFORM == 'java' ? :hot_bunny : :bunny
    self.queue_options    ||= {:durable => true, :arguments => {'x-ha-policy' => 'all'}}
    self.heartbeat        ||= 60
    self.bareback         ||= false
    self.hash_size        ||= 2**20 # one million keys ~ 200Mb.
    self.recovery         ||= false
    self.prefetch         ||= 1000
    self.recovery_timeout ||= 1.minute
    self.logger           ||= defined?(Rails) ? Rails.logger : Logger.new(STDERR).tap { |l| l.level = Logger::WARN }

    Celluloid.exception_handler { |e| Promiscuous::Config.error_notifier.try(:call, e) }
    Celluloid.logger = Promiscuous::Config.logger

    unless self.app
      raise "Promiscuous.configure: please give a name to your app with \"config.app = 'your_app_name'\""
    end

    # amqp connection is done in when setting the backend
    Promiscuous::Redis.connect

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
