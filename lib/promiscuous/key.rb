class Promiscuous::Key
  def initialize(role, nodes=[], no_join=nil)
    @role = role
    @nodes = nodes
    @no_join = no_join
  end

  def join(*nodes)
    # --- backward compatiblity code ---
    # TODO remove code
    if nodes == ['global', nil, nil]
      return self.class.new(@role, @nodes + nodes, :no_join)
    end
    if @no_join
      return self.class.new(@role, @nodes)
    end
    # --- backward compatiblity code ---

    self.class.new(@role, @nodes + nodes)
  end

  def to_s
    path = []
    case @role
    when :pub then path << 'publishers'
    when :sub then path << 'subscribers'
    end
    path << Promiscuous::Config.app
    path += @nodes.compact
    path.join(':')
  end

  def as_json(options={})
    to_s
  end
end
