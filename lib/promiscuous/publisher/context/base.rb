class Promiscuous::Publisher::Context::Base
  # XXX Context are not sharable among threads

  def self.current
    Thread.current[:promiscuous_context] ||= self.new
  end

  attr_accessor :current_user

  def transaction_context_of(driver)
    @transaction_managers ||= {}
    @transaction_managers[driver] ||= Promiscuous::Publisher::Context::Transaction.new(driver)
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
