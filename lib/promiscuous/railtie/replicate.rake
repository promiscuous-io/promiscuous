namespace :promiscuous do
  desc 'Run the subscribers worker'
  task :replicate => :environment do |t|
    require 'promiscuous/worker'
    require 'eventmachine'
    require 'em-synchrony'

    EM.synchrony do
      Promiscuous::Loader.load_descriptors :subscribers
      Promiscuous::AMQP.disconnect
      Promiscuous::Config.backend = :rubyamqp
      Promiscuous::AMQP.connect

      Promiscuous::Worker.replicate
      puts "Replicating with #{Promiscuous::Subscriber.subscribers.count} subscribers"
    end
  end
end
