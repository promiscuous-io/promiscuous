class Promiscuous::Dependency
  attr_accessor :nodes, :version

  def initialize(*args)
    options = args.extract_options!
    @nodes = args.map(&:to_s)

    if Promiscuous::Config.hash_size.to_i > 0 && !options[:nohash]
      # We hash dependencies to have a O(1) memory footprint in Redis.
      @nodes = [@nodes.hash % Promiscuous::Config.hash_size.to_i]
    end
  end

  def key(role)
    Promiscuous::Key.new(role).join(@nodes)
  end

  def as_json(options={})
    [*@nodes, @version].join(':')
  end

  def self.parse(payload)
    case payload
    when /^([^:]+):([^:]+):(.+):([0-9]+)$/ then new($1, $2, $3).tap { |d| d.version = $4.to_i }
    when /^(.+):([0-9]+)$/                 then new($1, :nohash => true).tap { |d| d.version = $2.to_i }
    else raise "Cannot parse #{payload} as a dependency"
    end
  end

  def to_s
    as_json
  end

  # We need the eql? method to function properly (we use ==, uniq, ...) in operation
  # XXX The version is not taken in account.
  def eql?(other)
    self.nodes == other.nodes
  end
  alias == eql?

  def hash
    self.nodes.hash
  end
end
