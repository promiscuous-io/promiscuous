class Promiscuous::Key
  def initialize(role, nodes=[])
    @role = role
    @nodes = nodes
  end

  def join(*nodes)
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
