require 'rubygems'
require 'bundler'
Bundler.require

MONGOID_HOST = ENV['MONGOID_SPEC_HOST'] || 'localhost'
MONGOID_PORT = ENV['MONGOID_SPEC_PORT'] || '27017'
DATABASE = 'promiscuous_test'

gemfile = File.basename(File.realpath(Bundler.default_gemfile), '.gemfile')
ENV['TEST_ENV'] = gemfile == 'Gemfile' ? 'mongoid3' : gemfile
load "./spec/spec_helper/#{ENV['TEST_ENV']}.rb"

Dir["./spec/support/**/*.rb"].each {|f| require f}

RSpec.configure do |config|
  config.mock_with :mocha
  config.color_enabled = true

  config.include AsyncHelper
  config.include BackendHelper
  config.include ModelsHelper
  config.include ObserversHelper
  config.include EphemeralsHelper
  config.include CallbacksHelper

  config.after { Promiscuous::Loader.cleanup }
end

Promiscuous::CLI.new.trap_debug_signals
load './debug.rb' if File.exists?('./debug.rb')
