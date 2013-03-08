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

  s.add_dependency "activesupport",       ">= 3.0.0"
  s.add_dependency "activemodel",         ">= 3.0.0"
  s.add_dependency "bunny",               ">= 0.9.0.pre7"
  s.add_dependency "amqp",                "~> 0.9.8"
  s.add_dependency "ruby-progressbar",    "~> 1.0.2"
  s.add_dependency "redis",               "~> 3.0.2"
  s.add_dependency "celluloid",           "~> 0.12.4"
  s.add_dependency "celluloid-io",        "~> 0.12.1"
  s.add_dependency "algorithms",          "~> 0.6.1"

  s.files        = Dir["lib/**/*"] + Dir["bin/**/*"]
  s.require_path = 'lib'
  s.has_rdoc     = false
end
