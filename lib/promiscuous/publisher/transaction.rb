class Promiscuous::Publisher::Transaction
  # XXX Transactions are not sharable among threads

  def self.open(*args, &block)
    old_disabled, self.disabled = self.disabled, false
    old_current, self.current = self.current, new(*args)

    begin
      self.current.reset
      self.current.alt_trace ">>> open >>>", :backtrace => :none if ENV['TRACE']
      yield
    ensure
      if ENV['TRACE']
        extra = "\e[1;31m(trailing reads)\e[0m " if self.current.sent_dummy?
        self.current.alt_trace "<<< close #{extra} <<<", :backtrace => :none
      end

      self.current.commit
      self.current = old_current
      self.disabled = old_disabled
    end
  end

  def self.current
    Thread.current[:promiscuous_transaction]
  end

  def self.current=(value)
    Thread.current[:promiscuous_transaction] = value
  end

  def self.disabled
    Thread.current[:promiscuous_disabled] || $promiscuous_disabled
  end

  def self.disabled=(value)
    Thread.current[:promiscuous_disabled] = value
  end

  attr_accessor :name, :operations, :retried, :nesting, :without_read_dependencies
  attr_accessor :last_written_dependency, :commited_childrens

  def initialize(*args)
    @parent = self.class.current
    @nesting = @parent.try(:nesting).to_i + 1
    @name = args.first.try(:to_s)
    @name ||= "#{@parent.next_child_name}" if @parent
    @name ||= 'anonymous'
    @operations = []
    @commited_childrens = []
    Promiscuous::AMQP.ensure_connected
  end

  def reset
    Mongoid::IdentityMap.clear if defined?(Mongoid::IdentityMap)
    @next_child = 0
  end

  def next_child_name
    @next_child += 1
    "#{name}/#{@next_child}"
  end

  def sent_dummy?
    !!@sent_dummy
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
    name = '  ' * @nesting + name
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

  def commit_child(child)
    @commited_childrens << child.name
    @last_written_dependency = child.last_written_dependency if child.last_written_dependency
  end

  def with_next_batch
    # We dequeue operations in N reads + 1 write bundle.
    read_dependencies = []
    while @operations.present? && @operations.first.read?
      read_operation = @operations.shift
      read_dependencies << read_operation.commited_dependencies.try(:first)
    end
    # Some operations may not have succeeded, so we weed out the dependencies
    # of failed operations.
    read_dependencies.compact!

    write_operation = @operations.shift
    write_dependencies = write_operation.try(:commited_dependencies) || []

    yield(write_operation, read_dependencies, write_dependencies)
  end

  def for_all_batches
    while @operations.present?
      with_next_batch do |write_operation, read_dependencies, write_dependencies|
        yield(write_operation, read_dependencies, write_dependencies)
      end
    end
  end

  def commit
    for_all_batches do |write_operation, read_dependencies, write_dependencies|
      options = {:transaction => self.name}
      # We need to consider the last write operation as an implicit read
      # dependency. This is why we don't need to consider the read dependencies
      # of the first write when publishing the second write.
      # TODO increment the link counter, and treat it as a real read dependency
      options[:dependencies] = {}
      options[:dependencies][:link] = @last_written_dependency if @last_written_dependency
      options[:dependencies][:read] = read_dependencies if read_dependencies.present?

      if write_operation && write_operation.instance
        if write_operation.failed?
          # If the operation has failed, then we do a dummy operation on the
          # failed instance. It's better than using the Dummy class because a
          # subscriber can choose not to receive any of these messages.
          # We don't publish anything if we didn't touch any dependencies
          # counters.
          return if read_dependencies.empty? && write_dependencies.empty?
          options[:operation] = :dummy
        else
          options[:operation] = write_operation.operation
        end

        # Sometimes the write_dependencies are not present. update/destroy operations
        # can miss the selector in a race with another destroy for example. So there
        # is nothing to lock, and so we have no write dependencies.
        if write_dependencies.present?
          options[:dependencies][:write] = write_dependencies
          # The best dependency (id) will always be first
          @last_written_dependency = write_dependencies.first
        end

        write_operation.instance.promiscuous.publish(options)
      else
        # We have to send the remaining read dependencies to the subscriber,
        # but we have no context, so we'll have to use a Dummy class to
        # ship them to the subscriber.
        # Note that we cannot have write_dependencies since write_operation
        # doesn't have an instance.
        Dummy.new.promiscuous.publish(options) if read_dependencies.present?
        @sent_dummy = true
        # We don't need to send a link to the dummy to the next operation
        # because we haven't written anything.
      end
    end

    @parent.try(:commit_child, self)
  rescue Promiscuous::Error::Publisher => e
    # arh, publishing miserably failed, that's bad news.
    # Now we are out of sync...
    # TODO write all of the remaining batches to the log file.
    raise e
  end

  class Dummy
    include Promiscuous::Publisher::Model::Ephemeral
    publish :to => '__promiscuous__/dummy'

    class PromiscuousMethods
      include Promiscuous::Publisher::Model::Base::PromiscuousMethodsBase

      def payload(options={})
        msg = {}
        msg[:__amqp__]     = @instance.class.publish_to
        msg[:operation]    = :dummy
        msg[:dependencies] = options[:dependencies]
        msg
      end
    end
  end
end
