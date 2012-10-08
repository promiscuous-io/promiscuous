require 'rubygems'
require 'bundler'
Bundler.require

MONGOID_HOST = ENV['MONGOID_SPEC_HOST'] || 'localhost'
MONGOID_PORT = ENV['MONGOID_SPEC_PORT'] || '27017'
DATABASE = 'promiscuous_test'

gemfile = File.realpath(Bundler.default_gemfile)
ENV['TEST_ENV'] = File.basename(gemfile, '.gemfile')
load "./spec/spec_helper/#{ENV['TEST_ENV']}.rb"

Dir["./spec/support/**/*.rb"].each {|f| require f}

RSpec.configure do |config|
  config.mock_with :mocha
  config.color_enabled = true

  config.include AsyncHelper
  config.include AMQPHelper
  config.include ModelsHelper
  config.include ObserversHelper

  config.after do
    Promiscuous::AMQP.disconnect
    Promiscuous::Worker.stop
    Promiscuous::Subscriber::AMQP.subscribers.clear
  end
end

