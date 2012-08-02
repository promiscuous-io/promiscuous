require 'rubygems'
require 'bundler'
Bundler.require(:default, :test)

require 'replicable/amqp'
Dir["./spec/support/**/*.rb"].each {|f| require f}

HOST = ENV['MONGOID_SPEC_HOST'] || 'localhost'
PORT = ENV['MONGOID_SPEC_PORT'] || '27017'
DATABASE = 'replicable_test'

mongoid3 = Gem.loaded_specs['mongoid'].version >= Gem::Version.new('3.0.0')

Mongoid.configure do |config|
  if mongoid3
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

  config.include AsyncHelper
  config.include AMQPHelper

  config.before(:each) do
  if mongoid3
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
