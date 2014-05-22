Mongoid.configure do |config|
  uri = ENV['BOXEN_MONGODB_URL']
  uri ||= "mongodb://localhost:27017/"
  uri += "#{DATABASE}"

  config.sessions = { :default => { :uri => uri } }

  if ENV['LOGGER_LEVEL']
    Moped.logger = Logger.new(STDOUT).tap { |l| l.level = ENV['LOGGER_LEVEL'].to_i }
  end
end

RSpec.configure do |config|
  config.before(:each) do
    Mongoid::Sessions.disconnect
    Mongoid.purge!
  end
end

# Backward compatible inc
module Mongoid::Persistable::Incrementable
  alias_method :orig_inc, :inc
  def inc(*args)
    if args.first.is_a?(Hash)
      orig_inc(*args)
    else
      args = { args[0] => args[1] }
      orig_inc(args)
    end
  end
end
