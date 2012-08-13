Mongoid.configure do |config|
  database = Mongo::Connection.new(MONGOID_HOST, MONGOID_PORT.to_i).db(DATABASE)
  config.master = database
  config.logger = nil
end

RSpec.configure do |config|
  config.before(:each) do
    Mongoid.database.collections.each do |collection|
      unless collection.name.include?('system')
        collection.remove
      end
    end
    Mongoid::IdentityMap.clear
  end
end
