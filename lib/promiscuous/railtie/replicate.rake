namespace :promiscuous do
  # Note These rake tasks can be loaded without Rails

  def trap_signals
    %w(SIGTERM SIGINT).each do |signal|
      Signal.trap(signal) do
        Promiscuous.info "Exiting..."
        Promiscuous::Worker.stop
        EM.stop
      end
    end
  end

  def print_status(msg)
    Promiscuous.info msg
    $stderr.puts msg
  end

  def force_backend(backend)
    Promiscuous::AMQP.disconnect
    Promiscuous::Config.backend = backend
    Promiscuous::AMQP.connect
  end

  def replicate(config_options={}, &block)
    require 'eventmachine'
    require 'em-synchrony'

    EM.synchrony do
      trap_signals
      Promiscuous::Loader.load_descriptors if defined?(Rails)
      force_backend :rubyamqp
      block.call
    end
  end

  desc 'Run the publisher worker'
  task :publish => :environment do
    replicate do
      Promiscuous::Worker.replicate :only => :publish
      print_status "Replicating with #{Promiscuous::Publisher::Mongoid::Defer.klasses.count} publishers"
    end
  end

  desc 'Run the subscriber worker'
  task :subscribe => :environment do
    replicate do
      Promiscuous::Worker.replicate :only => :subscribe
      print_status "Replicating with #{Promiscuous::Subscriber::AMQP.subscribers.count} subscribers"
    end
  end

  namespace :synchronized do
    desc 'Synchronize a collection'
    task :publish, [:criteria] => :environment do |t, args|
      raise "Usage: rake promiscuous:synchronized:publish[Model]" unless args.criteria

      criteria = eval(args.criteria)
      count = criteria.count
      print_status "Replicating #{args.criteria}..."

      bar = ProgressBar.create(:format => '%t |%b>%i| %c/%C %e',
                               :title => 'Publishing',
                               :total => count)
      criteria.each do |doc|
        doc.promiscuous_sync :personality => :sync
        bar.increment
      end

      print_status "Done. You may switch your subscriber worker back to regular mode, and delete the sync queues"
    end

    desc 'Subscribe to a collection synchronization'
    task :subscribe => :environment do |t|
      replicate do
        # Create the regular queue if needed, so we don't lose messages.
        Promiscuous::AMQP.open_queue(Promiscuous::Subscriber::Worker.new.queue_bindings)

        print_status "WARNING: --- SYNC MODE ----"
        print_status "WARNING: Make sure you are not running the regular subscriber worker (it's racy)"
        print_status "WARNING: --- SYNC MODE ----"
        Promiscuous::Worker.replicate :personality => :sync, :only => :subscribe
        print_status "Replicating with #{Promiscuous::Subscriber::AMQP.subscribers.count} subscribers"
      end
    end
  end
end
