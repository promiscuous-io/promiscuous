class Promiscuous::CLI
  attr_accessor :options

  def trap_signals
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

    %w(SIGTERM SIGINT).each do |signal|
      Signal.trap(signal) do
        print_status "Exiting..."
        @worker.terminate if @worker.try(:alive?)
        @stop = true
      end
    end
  end

  def publish
    options[:criterias].map { |criteria| eval(criteria) }.each do |criteria|
      break if @stop
      title = criteria.name
      title = "#{title}#{' ' * [0, 20 - title.size].max}"
      bar = ProgressBar.create(:format => '%t |%b>%i| %c/%C %e', :title => title, :total => criteria.count)
      criteria.each do |doc|
        break if @stop
        doc.promiscuous_sync
        bar.increment
      end
    end
  end

  def subscribe
    Promiscuous::Loader.load_descriptors if defined?(Rails)
    @worker = Promiscuous::Subscriber::Worker.run!
    Celluloid::Actor[:pump].subscribe_sync.wait
    print_status "Replicating with #{Promiscuous::Subscriber::AMQP.subscribers.count} subscribers"
    sleep 1 until !@worker.alive?
  end

  def generate_mocks(options)
    f = options[:output] ? File.open(options[:output], 'w') : STDOUT
    Promiscuous::Publisher::MockGenerator.new(f).generate
  ensure
    f.close rescue nil
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

    case options[:action]
    when :publish   then raise "Please specify one or more criterias" unless options[:criterias].present?
    when :subscribe then raise "Why are you specifying a criteria?"   if     options[:criterias].present?
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
    when :mocks     then generate_mocks(options)
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
