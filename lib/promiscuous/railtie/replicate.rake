namespace :promiscuous do
  desc 'Run the subscribers worker'
  task :replicate, [:initializer] => :environment do |t, args|
    require 'promiscuous/worker'
    require 'eventmachine'
    require 'em-synchrony'
    EM.synchrony do
      load args.initializer
      Promiscuous::Worker.replicate
    end
  end
end
