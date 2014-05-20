class Promiscuous::Publisher::Transport::Persistence
  extend Promiscuous::Autoload
  autoload :Mongoid, :ActiveRecord

  def save(batch)
    # Implemented by subclasses
    raise
  end

  def expired
    # Implemented by subclasses
    raise
  end
end
