# encoding: utf-8
$:.unshift File.expand_path("../lib", __FILE__)
$:.unshift File.expand_path("../../lib", __FILE__)

require 'promiscuous/version'

Gem::Specification.new do |s|
  s.name        = "promiscuous"
  s.version     = Promiscuous::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Nicolas Viennot", "Kareem Kouddous"]
  s.email       = ["nicolas@viennot.biz", "kareem@doubleonemedia.com"]
  s.homepage    = "http://github.com/crowdtap/promiscuous"
  s.summary     = "Model replication over RabbitMQ"
  s.description = "Replicate your Mongoid/ActiveRecord models across your applications"

  s.executables   = ['promiscuous']

  s.add_dependency("activesupport")
  s.add_dependency("activemodel")
  s.add_dependency("bunny")
  s.add_dependency("amqp")
  s.add_dependency("em-synchrony")
  s.add_dependency("ruby-progressbar")
  s.add_dependency("redis")
  s.add_dependency("crowdtap_redis_lock")

  s.files        = Dir["lib/**/*"] + Dir["bin/**/*"] + ['README.md']
  s.require_path = 'lib'
  s.has_rdoc     = false
end
