Mongoid.configure do |config|
  config.connect_to(DATABASE, :safe => true)
  ::BSON = ::Moped::BSON
  if ENV['LOGGER_LEVEL']
    Moped.logger = Logger.new(STDOUT).tap { |l| l.level = ENV['LOGGER_LEVEL'].to_i }
  end
end

RSpec.configure do |config|
  config.before(:each) do
    Mongoid.purge!
    Mongoid::IdentityMap.clear
  end
end
