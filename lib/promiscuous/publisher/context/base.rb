class Promiscuous::Publisher::Context::Base
  # XXX Context are not sharable among threads

  def self.current
    Thread.current[:promiscuous_context]
  end

  def self.current=(value)
    Thread.current[:promiscuous_context] = value
  end

  def self.with_context(*args, &block)
    raise "You cannot nest contexts" if self.current

    self.current = new(*args)
    begin
      self.current.trace "<<< open <<<", :level => 1
      yield
    ensure
      self.current.trace "<<< close <<<", :level => 1
      self.current = nil

      ActiveRecord::Base.clear_active_connections! if defined?(ActiveRecord::Base)
    end
  end

  attr_accessor :name, :read_operations, :extra_dependencies

  def initialize(*args)
    @name = args.first.try(:to_s) || 'anonymous'
    @read_operations = []
    @extra_dependencies = []
    @transaction_managers = {}

    Promiscuous::AMQP.ensure_connected

    Mongoid::IdentityMap.clear if defined?(Mongoid::IdentityMap)
    ActiveRecord::IdentityMap.clear if defined?(ActiveRecord::IdentityMap)
  end

  def transaction_context_of(driver)
    @transaction_managers[driver] ||= Promiscuous::Publisher::Context::Transaction.new(driver)
  end

  def trace_operation(operation, options={})
    msg = Promiscuous::Error::Dependency.explain_operation(operation, 70)
    trace(msg, options.merge(:color => operation.read? ? '0;32' : '1;31'))
  end

  def trace(msg, options={})
    level = ENV['TRACE'].to_i - options[:level].to_i
    return if level < 0

    backtrace = options[:backtrace]
    alt_fmt = options[:alt_fmt]
    color = options[:color] || "1;36"

    name = "  (#{self.name})#{' ' * ([0, 25 - self.name.size].max)}"
    STDERR.puts "\e[#{color}m#{name}#{alt_fmt ? '':'  '} #{msg}\e[0m"

    if level > 1 && defined?(Rails) && backtrace != :none
      bt = (backtrace || caller)
        .grep(/#{Rails.root}/)
        .map { |line| line.gsub(/#{Rails.root}\/?/, '') }
        .take(level-1)
        .map { |line| "\e[1;#{30}m#{name}     #{line}\e[0m" }
        .join("\n")
      STDERR.puts bt
    end
  end
end
