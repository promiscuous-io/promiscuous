namespace :replicable do
  desc 'Run the subscribers worker'
  task :run, [:initializer] => :environment do |t, args|
    require 'replicable/worker'
    require 'eventmachine'
    require 'em-synchrony'
    EM.synchrony do
      load args.initializer
      Replicable::Subscriber::Worker.run
    end
  end
end
