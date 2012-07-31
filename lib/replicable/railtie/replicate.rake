namespace :replicable do
  desc 'Run the subscribers worker'
  task :run do |t|
    require './spec/spec_helper'
    require 'replicable/subscriber/worker'
    require './spec/support/models'
    require 'eventmachine'
    EventMachine.run do
      Replicable::AMQP.configure(:backend => :rubyamqp, :app => 'sniper')
      Replicable::Subscriber::Worker.run
    end
  end
end
