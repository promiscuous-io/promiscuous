namespace :promiscuous do
  desc 'Run the subscribers worker'
  task :replicate => :environment do |t|
    require 'promiscuous/worker'
    require 'eventmachine'
    require 'em-synchrony'

    EM.synchrony do
      Promiscuous::Loader.load_descriptors :subscribers if defined?(Rails)
      Promiscuous::AMQP.disconnect
      Promiscuous::Config.backend = :rubyamqp
      Promiscuous::AMQP.connect

      Promiscuous::Worker.replicate
      $stderr.puts "Replicating with #{Promiscuous::Subscriber::AMQP.subscribers.count} subscribers"
    end
  end
end
