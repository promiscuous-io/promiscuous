class Promiscuous::CLI
  attr_accessor :options

  def trap_debug_signals
    Signal.trap 'SIGUSR2' do
      Thread.list.each do |thread|
        print_status  '----[ Threads ]----' + '-' * (100-19)
        if thread.backtrace
          print_status "Thread #{thread} #{thread['label']}"
          print_status thread.backtrace.join("\n")
        else
          print_status "Thread #{thread} #{thread['label']} -- no backtrace"
        end
      end

      # XXX Not thread safe (msg has some "@xxx ||= xxx" patterns)
      if blocked_messages = Celluloid::Actor[:message_synchronizer].try(:blocked_messages)
        print_status  '----[ Pending Dependencies ]----' + '-' * (100-32)
        blocked_messages.reverse_each { |msg| print_status msg }
      end
      print_status  '-' * 80
    end
  end

  def trap_exit_signals
    %w(SIGTERM SIGINT).each do |signal|
      Signal.trap(signal) do
        exit 1 if @stop
        print_status "Exiting..."
        @worker.terminate if @worker.try(:alive?)
        @stop = true
      end
    end
  end

  def trap_signals
    trap_debug_signals
    trap_exit_signals
  end

  def publish
    options[:criterias].map { |criteria| eval(criteria) }.each do |criteria|
      break if @stop
      title = criteria.name
      title = "#{title}#{' ' * [0, 20 - title.size].max}"
      bar = ProgressBar.create(:format => '%t |%b>%i| %c/%C %e', :title => title, :total => criteria.count)
      criteria.unscoped.each do |doc|
        break if @stop
        Promiscuous.context("cli/sync") { doc.promiscuous.sync }
        bar.increment
      end
    end
  end

  def replay
    require 'json'
    File.open(options[:log_file], 'r').each do |line|
      break if @stop
      case line
      when /^\[promiscuous\] \[receive\] ({.*})$/ then replay_payload($1)
      when /^\[promiscuous\] \[publish\] .* -> ({.*})$/ then replay_payload($1)
      end
    end
  end

  def subscribe
    @worker = Promiscuous::Subscriber::Worker.run!
    Celluloid::Actor[:pump].wait_for_subscription
    print_status "Replicating..."
    sleep 0.2 until !@worker.alive?
  end

  def generate_mocks
    f = options[:output] ? File.open(options[:output], 'w') : STDOUT
    f.write Promiscuous::Publisher::MockGenerator.generate
  end

  def replay_payload(payload)
    endpoint = JSON.parse(payload)['__amqp__']
    if endpoint
      Promiscuous::AMQP.publish(:key => endpoint, :payload => payload)
    else
      puts "[warn] missing destination in #{payload}"
    end
  end

  def publisher_recovery
    @worker = Promiscuous::Publisher::Worker.run!
    print_status "Waiting for messages to recover..."
    sleep 0.2 until !@worker.alive?
  end

  def parse_args(args)
    options = {}

    require 'optparse'
    parser = OptionParser.new do |opts|
      opts.banner = "Usage: promiscuous [options] action"

      opts.separator ""
      opts.separator "Actions:"
      opts.separator "    promiscuous publish \"Model1.where(:updated_at.gt => 1.day.ago)\" Model2 Model3..."
      opts.separator "    promiscuous subscribe"
      opts.separator "    promiscuous mocks"
      opts.separator "    promiscuous replay logfile"
      opts.separator "    promiscuous publisher_recovery"
      opts.separator ""
      opts.separator "Options:"

      opts.on "-b", "--bareback", "Bareback mode aka no dependencies. Use with extreme caution" do
        Promiscuous::Config.bareback = true
      end

      opts.on "-l", "--require FILE", "File to require to load your app. Don't worry about it with rails" do |file|
        options[:require] = file
      end

      opts.on "-r", "--recovery", "Run in recovery mode" do
        Promiscuous::Config.recovery = true
      end

      opts.on "-p", "--prefetch [NUM]", "Number of messages to prefetch" do |prefetch|
        exit 1 if prefetch.to_i == 0
        Promiscuous::Config.prefetch = prefetch.to_i
      end

      opts.on "-o", "--output FILE", "Output file for mocks. Defaults to stdout" do |file|
        options[:output] = file
      end

      opts.on "-s", "--stat-interval [DURATION]", "Stats refresh rate (0 to disable)" do |duration|
        Promiscuous::Config.stats_interval = duration.to_f
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
    options[:criterias] = args
    options[:log_file] = args.first

    case options[:action]
    when :publish   then raise "Please specify one or more criterias" unless options[:criterias].present?
    when :subscribe then raise "Why are you specifying a criteria?"   if     options[:criterias].present?
    when :replay    then raise "Please specify a log file to replay"  unless options[:log_file].present?
    when :publisher_recovery
    when :mocks
    else puts parser; exit 1
    end

    options
  rescue SystemExit
    exit
  rescue Exception => e
    puts e
    exit
  end

  def load_app
    if options[:require]
      require options[:require]
    else
      require 'rails'
      require 'promiscuous/railtie'
      require File.expand_path("./config/environment")
      ::Rails.application.eager_load!
    end
  end

  def boot
    self.options = parse_args(ARGV)
    load_app
    show_bareback_warnings
    run
  end

  def run
    trap_signals
    case options[:action]
    when :publish   then publish
    when :subscribe then subscribe
    when :replay    then replay
    when :mocks     then generate_mocks
    when :publisher_recovery then publisher_recovery
    end
  end

  def show_bareback_warnings
    if Promiscuous::Config.bareback == true
      print_status "WARNING: --- BAREBACK MODE ----"
      print_status "WARNING: You are replicating without protection, you can get out of sync in no time"
      print_status "WARNING: --- BAREBACK MODE ----"
    end
  end

  def print_status(msg)
    Promiscuous.info msg
    $stderr.puts msg
  end
end
