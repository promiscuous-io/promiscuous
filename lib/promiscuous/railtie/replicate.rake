namespace :promiscuous do
  # Note This rake task can be loaded without Rails
  desc 'Run the workers'
  task :replicate => :environment do |t|
    require 'eventmachine'
    require 'em-synchrony'

    EM.synchrony do
      trap_signals
      force_backend :rubyamqp

      Promiscuous::Loader.load_descriptors if defined?(Rails)

      Promiscuous::Subscriber::Worker.replicate
      $stderr.puts "Replicating with #{Promiscuous::Subscriber::AMQP.subscribers.count} subscribers"
    end
  end

  def trap_signals
    %w(SIGTERM SIGINT).each do |signal|
      Signal.trap(signal) do
        Promiscuous.info "Exiting..."
        EM.stop
      end
    end
  end

  def force_backend(backend)
    Promiscuous::AMQP.disconnect
    Promiscuous::Config.backend = backend
    Promiscuous::AMQP.connect
  end
end
