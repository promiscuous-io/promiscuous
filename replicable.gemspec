# encoding: utf-8
$:.unshift File.expand_path("../lib", __FILE__)

require 'replicable/version'

Gem::Specification.new do |s|
  s.name        = "replicable"
  s.version     = Replicable::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Nicolas Viennot", "Kareem Kouddous"]
  s.email       = ["nicolas@viennot.biz", "kareem@doubleonemedia.com"]
  s.homepage    = "http://github.com/crowdtap/replicable"
  s.summary     = "Model replication over RabbitMQ"
  s.description = "Replicate data across your applications"

  s.add_dependency("mongoid", ">= 2.4")
  s.add_dependency("activesupport")
  s.add_dependency("bunny")
  s.add_dependency("amqp")
  s.add_dependency("em-synchrony")

  s.files        = Dir["lib/**/*"] + ['README.md']
  s.require_path = 'lib'
  s.has_rdoc     = false
end
