load './spec/support/_coverage.rb'
require 'rubygems'
require 'bundler'
Bundler.require

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
    config.default_retry_count = 5
  end
end

RSpec.configure do |config|
  config.mock_with :mocha
  config.color = true

  config.include AsyncHelper
  config.include BackendHelper
  config.include ModelsHelper
  config.include ObserversHelper
  config.include EphemeralsHelper
  config.include CallbacksHelper
  config.include DependencyHelper
  config.include MocksHelper

  I18n.enforce_available_locales = false

  config.after { Promiscuous::Loader.cleanup }
end

Promiscuous::CLI.new.trap_debug_signals
load './debug.rb' if File.exists?('./debug.rb')

module Promiscous
  def self.testing?
    true
  end
end

# To ensure that descendants list is ordered the same in mongoid 3x & 4x
module ActiveSupport::DescendantsTracker
  alias_method :orig_descendants, :descendants
  def descendants
    orig_descendants.sort { |x,y| x.to_s <=> y.to_s }
  end
end
