class Promiscuous::Railtie < Rails::Railtie
  module TransactionMiddleware
    def cleanup_controller
      self.instance_variables.grep(/^@[^:_]/).each do |var|
        instance_variable_set(var, nil)
      end
    end

    def process_action(*args)
      Promiscuous.transaction("#{self.class.controller_name}/#{self.action_name}") do
        cleanup_controller
        super
      end
    rescue Exception => e
      $promiscuous_last_exception = e if e.is_a? Promiscuous::Error::Base
      Promiscuous::Railtie.pretty_print_exception(e)
      raise e
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
    backtrace = e.backtrace
    .take_while { |line| line !~ /#{__FILE__}/ }
    .map do |line|
      line = case line
             when /`(count|distinct|each|first|last)'$/                     then "\e[1;32m#{line}\e[0m"
             when /`(create|insert|save|update|modify|remove|remove_all)'$/ then "\e[1;31m#{line}\e[0m"
             when /#{Rails.root}/                                           then "\e[1;36m#{line}\e[0m"
             else                                                                "\e[1;30m#{line}\e[0m" if ENV['TRACE']
             end
      "\e[0;#{36}m|  #{line}" if line
    end
    STDERR.puts backtrace.compact.join("\n")
    STDERR.puts "\e[0;#{36}m|"
    STDERR.puts "\e[0;#{36}m\\------------------------------------------------------------------------------------------------------\e[0m"
    STDERR.puts
    $promiscuous_pretty_print_exception_once = :disable if $promiscuous_pretty_print_exception_once
  end

  initializer 'load promiscuous' do
    config.after_initialize do
      Promiscuous::Config.configure unless Promiscuous::Config.configured?
      Promiscuous::Loader.prepare
      ActionController::Base.__send__(:include, TransactionMiddleware)

      ActionDispatch::Reloader.to_prepare do
        Promiscuous::Loader.prepare
      end
      ActionDispatch::Reloader.to_cleanup do
        Promiscuous::Loader.cleanup
      end
    end
  end
end
