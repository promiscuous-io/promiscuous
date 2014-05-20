class Promiscuous::Publisher::Transport
  extend Promiscuous::Autoload
  autoload :Batch, :Worker, :Persistence

  class_attribute :persistence

  if defined?(Mongoid::Document)
    self.persistence = Persistence::Mongoid.new
  elsif defined?(ActiveRecord::Base)
    self.persistence = Persistence::ActiveRecord.new
  else
    raise "Either Mongoid or ActiveRecord support required"
  end
end
