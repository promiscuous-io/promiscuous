require 'rubygems'
require 'bundler'
Bundler.require

require 'rspec/core/rake_task'
load 'replicable/railtie/replicate.rake'

RSpec::Core::RakeTask.new("spec") do |spec|
  spec.pattern = "spec/**/*_spec.rb"
end

task :default => :spec
