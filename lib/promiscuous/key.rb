class Promiscuous::Key
  def initialize(role, nodes=[])
    @role = role
    @nodes = nodes
  end

  def join(*nodes)
    self.class.new(@role, @nodes + nodes)
  end

  def for(service)
    path = []
    case @role
    when :pub then path << 'publishers'
    when :sub then path << 'subscribers'
    end
    path << Promiscuous::Config.app
    path += @nodes.compact
    case service
    when :redis then path.join(':')
    when :zk    then path.join('/')
    end
  end
end
