class Promiscuous::Publisher::Dependency < Struct.new(:collection, :attribute, :value, :version)
  def key
    Promiscuous::Key.new(:pub).join(collection, attribute, value)
  end

  def as_json(options={})
    [collection, attribute, value, version].join(':')
  end

  # Note that we need the == method to function properly.
  # See the 'ensure_up_to_date_dependencies' method in operation/base.rb
end
