require 'rubygems'
require 'bundler'
Bundler.require

require 'appraisal'

class Appraisal::Command
  def self.from_args(gemfile)
    if ARGV.size == 0
      command = 'rake spec'
    else
      command = ([$0] + ARGV.slice(1, ARGV.size)).join(' ')
    end
    new(command, gemfile)
  end
end

require 'rspec/core/rake_task'
load 'promiscuous/railtie/replicate.rake'

RSpec::Core::RakeTask.new("spec") do |spec|
  spec.pattern = "spec/**/*_spec.rb"
end

task :default => :appraisal
