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

  attr_accessor :name, :operations, :extra_dependencies

  def initialize(*args)
    @name = args.first.try(:to_s) || 'anonymous'
    @operations = []
    @extra_dependencies = []
    @transaction_indexes = {}

    Promiscuous::AMQP.ensure_connected

    Mongoid::IdentityMap.clear if defined?(Mongoid::IdentityMap)
    ActiveRecord::IdentityMap.clear if defined?(ActiveRecord::IdentityMap)
  end

  def start_transaction(driver)
    # The indexes are stored in a queue so we know which operation to mark as
    # failed.
    @transaction_indexes[driver] ||= []
    @transaction_indexes[driver] << @operations.size
  end

  def transaction_operations(driver)
    transaction_index = @transaction_indexes[driver].last
    @operations[transaction_index..-1].select { |op| op.transaction_context == driver }
  end

  def rollback_transaction(driver)
    transaction_operations(driver).each(&:fail!)
    @transaction_indexes[driver].pop
  end

  def commit_transaction(driver)
    @transaction_indexes[driver].pop
  end

  def in_transaction?(driver)
    !(@transaction_indexes[driver] || []).empty?
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
