class Promiscuous::Publisher::Context
  # XXX Context are not sharable among threads

  def self.open(*args, &block)
    old_disabled, Promiscuous.disabled = Promiscuous.disabled, false
    old_current, self.current = self.current, new(*args)

    begin
      self.current.alt_trace ">>> open >>>", :backtrace => :none if ENV['TRACE']
      yield
    ensure
      self.current.alt_trace "<<< close <<<", :backtrace => :none if ENV['TRACE']

      self.current.close
      self.current = old_current
      Promiscuous.disabled = old_disabled
    end
  end

  def self.current
    Thread.current[:promiscuous_context]
  end

  def self.current=(value)
    Thread.current[:promiscuous_context] = value
  end

  attr_accessor :name, :operations, :nesting_level, :last_write_dependency

  def initialize(*args)
    @parent = self.class.current
    @nesting_level = @parent.try(:nesting_level).to_i + 1
    @name = args.first.try(:to_s)
    @name ||= "#{@parent.next_child_name}" if @parent
    @name ||= 'anonymous'
    @operations = []
    @next_child = 0

    Promiscuous::AMQP.ensure_connected
    Mongoid::IdentityMap.clear if defined?(Mongoid::IdentityMap)
  end

  def close
    @parent.try(:close_child, self)
  end

  def close_child(child)
    @last_write_dependency = child.last_write_dependency if child.last_write_dependency
  end

  def next_child_name
    @next_child += 1
    "#{name}/#{@next_child}"
  end

  def add_operation(operation)
    @operations << operation
    trace_operation(operation) if ENV['TRACE']
  end

  def trace_operation(operation, options={})
    msg = Promiscuous::Error::Dependency.explain_operation(operation, 70)
    msg = msg.gsub(/(\(missed\))$/, "\e[1;#{30}m\\1")
    trace(msg, options.merge(:color => operation.read? ? '0;32' : '1;31'))
  end

  def alt_trace(msg, options={})
    trace(msg, options.merge(:alt_fmt => true))
  end

  def trace(msg, options={})
    backtrace = options[:backtrace]
    alt_fmt = options[:alt_fmt]
    color = alt_fmt ? "1;36" : options[:color]

    name = "(#{self.name})#{' ' * ([0, 25 - self.name.size].max)}"
    name = '  ' * @nesting_level + name
    STDERR.puts "\e[#{color}m#{name}#{alt_fmt ? '':'  '} #{msg}\e[0m"

    level = ENV['TRACE'].to_i
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
