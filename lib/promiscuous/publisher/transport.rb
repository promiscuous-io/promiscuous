class Promiscuous::Publisher::Transport
  extend Promiscuous::Autoload
  autoload :Batch, :Worker, :Persistence

  def self.persistence
    unless @persistence_key == Promiscuous::Config.transport_persistence
      fix_inflections
      @persistence = Persistence.const_get(Promiscuous::Config.transport_persistence.to_s.classify).new
      @persistence_key = Promiscuous::Config.transport_persistence
    end
    @persistence
  end

  private

  def self.fix_inflections
    ActiveSupport::Inflector.inflections do |inflect|
      inflect.uncountable "redis"
    end
  end
end
