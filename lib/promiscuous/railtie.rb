class Promiscuous::Railtie < Rails::Railtie
  module TransactionMiddleware
    extend ActiveSupport::Concern

    mattr_accessor :with_transactions
    self.with_transactions = {}

    def cleanup_controller
      request.body.rewind
      self.instance_variables.each do |var|
        remove_instance_variable(var) unless var.in?(@_prestine_vars)
      end
    end

    def process_action(*args)
      @_prestine_vars = []
      @_prestine_vars = self.instance_variables

      full_name = "#{self.class.controller_path}/#{self.action_name}"
      options = Promiscuous::Railtie::TransactionMiddleware.with_transactions[full_name]
      if options
        Promiscuous.transaction(full_name, options) do
          cleanup_controller
          super
        end
      else
        begin
          # That's for generating better errors traces
          Thread.current[:promiscuous_controller] = {:controller => self, :action => action_name}
          with_promiscuous { super }
        ensure
          Thread.current[:promiscuous_controller] = nil
        end
      end
    rescue Exception => e
      $promiscuous_last_exception = e if e.is_a? Promiscuous::Error::Base
      Promiscuous::Railtie.pretty_print_exception(e)
      raise e
    end

    def render(*args)
      without_promiscuous { super }
    end

    module ClassMethods
      def with_transaction(*args)
        options = args.extract_options!
        args.each do |action|
          full_name = "#{controller_path}/#{action}"
          Promiscuous::Railtie::TransactionMiddleware.with_transactions[full_name] = options
        end
      end
    end
  end

  def self.pretty_print_exception(e)
    return if $promiscuous_pretty_print_exception_once == :disable

    STDERR.puts
    STDERR.puts "\e[0;#{36}m/---[ Exception: #{e.class} ]#{'-'*[0, 84 - e.class.name.size].max}\e[0m"
    STDERR.puts "\e[0;#{36}m|"

    highlight_indent = false
    msg = e.to_s.split("\n").map do |line|
      highlight_indent = true if line =~ /The problem comes from the following/ ||
                                 line =~ /Promiscuous is tracking this read/
      line = "\e[1;#{31}m#{line}\e[0;#{31}m" if highlight_indent && line =~ /^  /
      "\e[0;#{36}m|  \e[0;#{31}m#{line}\e[0m"
    end

    STDERR.puts msg.join("\n")
    STDERR.puts "\e[0;#{36}m|"
    STDERR.puts "\e[0;#{36}m+---[ Backtrace ]--------------------------------------------------------------------------------------\e[0m"
    STDERR.puts "\e[0;#{36}m|"

    expand = ENV['TRACE'].to_i > 1
    bt = e.backtrace.map do |line|
       line = case line
              when /(rspec-core|instrumentation)/
                "\e[1;30m#{line}\e[0m" if expand
              when /#{Rails.root}\/app\/controllers/
                "\e[1;35m#{line}\e[0m"
              when /#{Rails.root}\/app\/models/
                "\e[1;33m#{line}\e[0m"
              when /#{Rails.root}\/lib/
                "\e[1;34m#{line}\e[0m"
              when /(mongoid|active_record).*`(count|distinct|each|first|last)'$/
                "\e[1;32m#{line}\e[0m"
              when /(mongoid|active_record).*`(create|insert|save|update|modify|remove|remove_all)'$/
                "\e[1;31m#{line}\e[0m"
              when /#{Rails.root}/
                if line =~ /\/support\//
                  "\e[1;30m#{line}\e[0m" if expand
                else
                  "\e[1;36m#{line}\e[0m"
                end
              else
                "\e[1;30m#{line}\e[0m" if expand
              end
       "\e[0;#{36}m|  #{line}" if line
      end
      .compact
      .join("\n")
    STDERR.puts bt
    STDERR.puts "\e[0;#{36}m|"
    STDERR.puts "\e[0;#{36}m\\------------------------------------------------------------------------------------------------------\e[0m"
    STDERR.puts
    $promiscuous_pretty_print_exception_once = :disable if $promiscuous_pretty_print_exception_once
  end

  initializer 'load promiscuous' do
    config.before_initialize do
      ActionController::Base.__send__(:include, TransactionMiddleware)
    end

    config.after_initialize do
      Promiscuous::Config.configure unless Promiscuous::Config.configured?
      Promiscuous::Loader.prepare

      ActionDispatch::Reloader.to_prepare do
        Promiscuous::Loader.prepare
      end
      ActionDispatch::Reloader.to_cleanup do
        Promiscuous::Loader.cleanup
      end
    end
  end
end
