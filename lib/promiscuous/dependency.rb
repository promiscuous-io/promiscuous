class Promiscuous::Dependency < Struct.new(:collection, :attribute, :value, :version)
  def key(role)
    Promiscuous::Key.new(role).join(collection, attribute, value)
  end

  def as_json(options={})
    [collection, attribute, value, version].join(':')
  end

  def self.parse(payload)
    case payload
    when /^([^:]+):([^:]+):(.+):([0-9]+)$/ then new($1, $2, $3, $4.to_i)
    # TODO remove backward compatibility code
    when /^global:([0-9]+)$/               then new('global', nil, nil, $1.to_i)
    else raise "Cannot parse #{payload} as a dependency"
    end
  end

  def to_s
    as_json
  end

  # Note that we need the == method to function properly.
  # See the 'ensure_up_to_date_dependencies' method in publisher/operation/base.rb
end
