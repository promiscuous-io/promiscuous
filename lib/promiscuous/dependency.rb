require 'fnv'

class Promiscuous::Dependency
  attr_accessor :internal_key, :version

  def initialize(*args)
    options = args.extract_options!
    @internal_key = args.join(':')

    if Promiscuous::Config.hash_size.to_i > 0 && !options[:nohash]
      # We hash dependencies to have a O(1) memory footprint in Redis.
      # The hashing needs to be deterministic across instances in order to
      # function properly.
      @internal_key = [FNV.new.fnv1a_32(@internal_key) % Promiscuous::Config.hash_size.to_i]
    end
  end

  def key(role)
    Promiscuous::Key.new(role).join(@internal_key)
  end

  def as_json(options={})
    [@internal_key, @version].join(':')
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
    self.internal_key == other.internal_key
  end
  alias == eql?

  def hash
    self.internal_key.hash
  end
end
