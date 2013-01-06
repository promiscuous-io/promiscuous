require 'promiscuous'

class Promiscuous::CLI
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

  def force_backend(backend)
    Promiscuous::AMQP.disconnect
    Promiscuous::Config.backend = backend
    Promiscuous::AMQP.connect
  end

  def trap_signals
    %w(SIGTERM SIGINT).each do |signal|
      Signal.trap(signal) do
        print_status "Exiting..."
        Promiscuous::Worker.kill
        EM.stop
      end
    end

    Signal.trap 'SIGUSR2' do
      Thread.list.each do |thread|
        print_status '-' * 80
        if thread.backtrace
          print_status "Thread #{thread} #{thread['label']}"
          print_status thread.backtrace.join("\n")
        else
          print_status "Thread #{thread} #{thread['label']} -- no backtrace"
        end
      end
    end
  end

  def publish(options={})
    replicate do
      Promiscuous::Worker.replicate(options)
      print_status "Replicating with #{Promiscuous::Publisher::Mongoid::Defer.klasses.count} publishers"
    end
  end

  def subscribe(options={})
    replicate do
      Promiscuous::Worker.replicate(options)
      print_status "Replicating with #{Promiscuous::Subscriber::AMQP.subscribers.count} subscribers"
    end
  end

  def publish_sync(options={})
    print_status "Replicating #{options[:criteria]}..."
    criteria = eval(options[:criteria])

    bar = ProgressBar.create(:format => '%t |%b>%i| %c/%C %e', :title => 'Publishing', :total => criteria.count)
    criteria.each do |doc|
      doc.promiscuous_sync(options)
      bar.increment
    end

    print_status "Done. You may switch your subscriber worker back to regular mode, and delete the sync queues"
  end

  def subscribe_sync(options={})
    replicate do
      # Create the regular queue if needed, so we don't lose messages.
      Promiscuous::AMQP.open_queue(Promiscuous::Subscriber::Worker.new.queue_bindings)

      print_status "WARNING: --- SYNC MODE ----"
      print_status "WARNING: Make sure you are not running the regular subscriber worker (it's racy)"
      print_status "WARNING: --- SYNC MODE ----"
      Promiscuous::Worker.replicate(options)
      print_status "Replicating with #{Promiscuous::Subscriber::AMQP.subscribers.count} subscribers"
    end
  end

  def parse_args(args)
    options = {}

    require 'optparse'
    parser = OptionParser.new do |opts|
      opts.banner = "Usage: promiscuous [options] action"

      opts.separator ""
      opts.separator "Actions:"
      opts.separator "    publish"
      opts.separator "    subscribe"
      opts.separator ""
      opts.separator "Options:"

      opts.on "-s", "--sync", "Use a separate queue for sychronizing databases" do
        options[:personality] = :sync
      end

      opts.on "-c", "--criteria CRITERIA", "Published criteria in sync mode. e.g. Member.where(:created_at.gt => 1.day.ago)" do |criteria|
        options[:criteria] = criteria
      end

      opts.on "-b", "--bareback", "Bareback mode aka continue on error. Use with extreme caution" do
        options[:bareback] = true
      end

      opts.on "-r", "--require FILE", "File to require to load your app. Don't worry about it with rails" do |file|
        options[:require] = file
      end

      opts.on("-h", "--help", "Show this message") do
        puts opts
        exit
      end

      opts.on("-V", "--version", "Show version") do
        puts "Promiscuous #{Promiscuous::VERSION}"
        puts "License MIT"
        exit
      end
    end

    args = args.dup
    parser.parse!(args)

    options[:action] = args.shift.try(:to_sym)
    raise "Please specify an action (publish or subscribe)" unless options[:action].in? [:publish, :subscribe]

    if options[:action] == :publish && options[:personality] == :sync
      raise "Please specify a criteria" unless options[:criteria]
    else
      raise "Why are you specifying a criteria?" if options[:criteria]
    end

    options
  end

  def load_app(options={})
    if options[:require]
      require options[:require]
    else
      require 'rails'
      require File.expand_path("./config/environment.rb")
      ::Rails.application.eager_load!
    end
  end

  def run
    options = parse_args(ARGV)
    load_app(options)
    maybe_warn_bareback(options)

    # calls publish, publish_sync, subscribe, subscribe_sync
    __send__([options[:action], options[:personality]].compact.join('_'), options)
  end

  def maybe_warn_bareback(options)
    if options[:bareback]
      print_status "WARNING: --- BAREBACK MODE ----"
      print_status "WARNING: You are replicating without protection, you can get corrupted in no time"
      print_status "WARNING: --- BAREBACK MODE ----"
    end
  end

  def print_status(msg)
    Promiscuous.info msg
    $stderr.puts msg
  end
end
