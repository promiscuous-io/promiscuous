require 'ruby-progressbar'

class Promiscuous::CLI
  attr_accessor :options

  def trap_debug_signals
    Signal.trap 'SIGUSR2' do
      # Using a thread because we cannot acquire mutexes in a trap context in
      # ruby 2.0
      Thread.new do
        Thread.list.each do |thread|
          next if Thread.current == thread

          print_status  '----[ Threads ]----' + '-' * (100-19)
          if thread.backtrace
            print_status "Thread #{thread} #{thread['label']}"
            print_status thread.backtrace.join("\n")
          else
            print_status "Thread #{thread} #{thread['label']} -- no backtrace"
          end
        end
      end
    end
  end

  def trap_exit_signals
    %w(SIGTERM SIGINT).each do |signal|
      Signal.trap(signal) do
        # Using a thread because we cannot acquire mutexes in a trap context in
        # ruby 2.0
        Thread.new do
          print_status "Exiting..."
          if @stop
            @worker.try(:show_stop_status)
          else
            @stop = true
            @worker.try(:stop)
            @worker = nil
          end
        end.join
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
      criteria.each do |doc|
        break if @stop
        doc.promiscuous.sync(Promiscuous::Config.sync_all_routing)
        bar.increment
      end
    end
  end

  def record
    @worker = Promiscuous::Subscriber::Worker::Recorder.new(options[:log_file])
    @worker.start
    print_status "Recording..."
    sleep 0.2 until !@worker
  end

  def replay_payload(payload)
    endpoint = MultiJson.load(payload)['__amqp__']
    if endpoint
      # TODO confirm
      Promiscuous::AMQP.publish(:key => endpoint, :payload => payload)
      @num_msg += 1
    else
      puts "[warn] missing destination in #{payload}"
    end
  end

  def replay
    require 'json'
    @num_msg = 0
    File.open(options[:log_file], 'r').each do |line|
      break if @stop
      case line
      when /^\[promiscuous\] \[receive\] ({.*})$/ then replay_payload($1)
      when /^\[promiscuous\] \[publish\] .* -> ({.*})$/ then replay_payload($1)
      when /^({.*})$/ then replay_payload($1)
      end
    end

    print_status "Replayed #{@num_msg} messages"
  end

  def subscribe
    @worker = Promiscuous::Subscriber::Worker.new
    @worker.start
    Promiscuous::Config.subscriber_threads.tap do |threads|
      print_status "Replicating [#{threads} thread#{'s' if threads > 1}]..."
    end
    sleep 0.2 until !@worker
  end

  def publisher_recovery
    @worker = Promiscuous::Publisher::Worker.new
    @worker.start
    print_status "Waiting for messages to recover..."
    sleep 0.2 until !@worker
  end

  def generate_mocks
    f = options[:output] ? File.open(options[:output], 'w') : STDOUT
    f.write Promiscuous::Publisher::MockGenerator.generate
  end

  def parse_args(args)
    options = {}

    require 'optparse'
    parser = OptionParser.new do |opts|
      opts.banner = "Usage: promiscuous [options] action"

      opts.separator ""
      opts.separator "Actions:"
      opts.separator "    promiscuous publish \"Model1.where(:updated_at.gt => 1.day.ago)\" [Model2 Model3...]"
      opts.separator "    promiscuous publisher_recovery"
      opts.separator "    promiscuous subscribe"
      opts.separator "    promiscuous migrations"
      opts.separator "    promiscuous mocks"
      opts.separator "    promiscuous record logfile"
      opts.separator "    promiscuous replay logfile"
      opts.separator ""
      opts.separator "Options:"

      opts.on "-l", "--require FILE", "File to require to load your app. Don't worry about it with rails" do |file|
        options[:require] = file
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

      opts.on "-t", "--threads [NUM]", "Number of subscriber worker threads to run. Defaults to 10." do |threads|
        Promiscuous::Config.subscriber_threads = threads.to_i
      end

      opts.on "-D", "--daemonize", "Daemonize process" do
        options[:daemonize] = true
      end

      opts.on "-P", "--pid-file [pid_file]", "Set a pid-file" do |pid_file|
        options[:pid_file] = pid_file
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
    when :publish             then raise "Please specify one or more criterias" unless options[:criterias].present?
    when :subscribe           then raise "Why are you specifying a criteria?"   if     options[:criterias].present?
    when :record              then raise "Please specify a log file to record"  unless options[:log_file].present?
    when :replay              then raise "Please specify a log file to replay"  unless options[:log_file].present?
    when :publisher_recovery
    when :migrations
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
      begin
        require options[:require]
      rescue LoadError
        require "./#{options[:require]}"
      end
    else
      require 'rails'
      require 'promiscuous/railtie'
      require File.expand_path("./config/environment")
      ::Rails.application.eager_load!
    end
  end

  def boot
    self.options = parse_args(ARGV)
    daemonize if options[:daemonize]
    write_pid if options[:pid_file]
    load_app
    run
  end

  def daemonize
    Process.daemon(true)
  end

  def write_pid
    File.open(options[:pid_file], 'w') do |f|
      f.puts Process.pid
    end
  end

  def run
    trap_signals
    case options[:action]
    when :publish   then publish
    when :subscribe then subscribe
    when :record    then record
    when :replay    then replay
    when :migrations then check_migrations
    when :mocks     then generate_mocks
    when :publisher_recovery  then publisher_recovery
    end
  end

  def print_status(msg)
    Promiscuous.info msg
    STDERR.puts msg
  end

  def check_migrations
    if Promiscuous::Config.transport_persistence == :active_record
      unless ActiveRecord::Base.connection.table_exists?(Promiscuous::Config.transport_collection)
        puts <<-help
Promiscuous requires the following migration to be run:
  create_table :_promiscuous do |t|
    t.text      :batch
    t.timestamp :at, 'TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP'
  end
        help
      end

      Promiscuous::Publisher::Model::ActiveRecord.check_migrations
      Promiscuous::Subscriber::Model::ActiveRecord.check_migrations
    end
  end
end
