load './spec/support/_coverage.rb'
require 'rubygems'
require 'bundler'
Bundler.require

MONGOID_HOST = ENV['MONGOID_SPEC_HOST'] || 'localhost'
MONGOID_PORT = ENV['MONGOID_SPEC_PORT'] || '27017'
DATABASE = 'promiscuous_test'

gemfile = File.basename(File.realpath(Bundler.default_gemfile), '.gemfile')

case gemfile
when 'Gemfile'   then ENV['TEST_ENV'] = 'mongoid3'
when 'mongoid31' then ENV['TEST_ENV'] = 'mongoid3'
else
  ENV['TEST_ENV'] = gemfile
end
load "./spec/spec_helper/#{ENV['TEST_ENV']}.rb"

Dir["./spec/support/**/*.rb"].each {|f| require f}

if ENV['TRAVIS']
  require 'rspec/retry'
  RSpec.configure do |config|
    config.verbose_retry = true
    config.default_retry_count = 3
  end
end

RSpec.configure do |config|
  config.mock_with :mocha
  config.color_enabled = true

  config.include AsyncHelper
  config.include BackendHelper
  config.include ModelsHelper
  config.include ObserversHelper
  config.include EphemeralsHelper
  config.include CallbacksHelper
  config.include DependencyHelper
  config.include MocksHelper

  config.after { Promiscuous::Loader.cleanup }
end

Promiscuous::CLI.new.trap_debug_signals
load './debug.rb' if File.exists?('./debug.rb')

module Promiscous
  def self.testing?
    true
  end
end
