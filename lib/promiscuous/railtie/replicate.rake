namespace :promiscuous do
  desc 'Run the subscribers worker'
  task :replicate, [:initializer] => :environment do |t, args|
    require 'promiscuous/worker'
    require 'eventmachine'
    require 'em-synchrony'

    EM.synchrony do
      Promiscuous::Loader.load_descriptors :subscribers
      load args.initializer
      Promiscuous::Worker.replicate
      puts "Promiscuous is ready to replicate"
    end
  end
end
