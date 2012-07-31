require 'rubygems'
require 'bundler'
Bundler.require(:default, :test)

require 'replicable/amqp'
Replicable::AMQP.configure

HOST = ENV['MONGOID_SPEC_HOST'] || 'localhost'
PORT = ENV['MONGOID_SPEC_PORT'] || '27017'
DATABASE = 'replicable_test'

Mongoid.configure do |config|
  if Replicable.mongoid3
    config.connect_to(DATABASE)
    ::BSON = ::Moped::BSON
  else
    database = Mongo::Connection.new(HOST, PORT.to_i).db(DATABASE)
    config.master = database
    config.logger = nil
  end
end

RSpec.configure do |config|
  config.mock_with :mocha
  config.color_enabled = true

  config.before(:each) do
  if Replicable.mongoid3
      Mongoid.purge!
    else
      Mongoid.database.collections.each do |collection|
        unless collection.name.include?('system')
          collection.remove
        end
      end
    end
    Mongoid::IdentityMap.clear
  end
end
