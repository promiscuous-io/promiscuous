class Promiscuous::Publisher::Context::Middleware < Promiscuous::Publisher::Context::Base
  module Controller
    extend ActiveSupport::Concern

    def process_action(*args)
      full_name = "#{self.class.controller_path}/#{self.action_name}"
      current_user_id = self.respond_to?(:current_user) ? self.current_user.try(:id) : nil
      Promiscuous::Publisher::Context::Middleware.with_context(full_name, current_user_id) { super }
    end

    def render(*args)
      Promiscuous::Publisher::Context::Middleware.without_context { super }
    end
  end

  def self.with_context(*args, &block)
    # XXX We turn off the disabled flag when entering a middleware.
    # It has priority because it's much simpler to use for testing.
    old_disabled, Promiscuous.disabled = Promiscuous.disabled?, false
    super
  rescue Exception => e
    $promiscuous_last_exception = e if e.is_a? Promiscuous::Error::Base
    pretty_print_exception(e)
    raise e
  ensure
    Promiscuous.disabled = old_disabled
  end

  def self.without_context
    # This is different from the method without_promiscuous in convenience.rb
    # That's used for render() and things that are *not* supposed to write.
    # We actually force promiscuous to instrument queries, and make sure that
    # we don't do any writes we shouldn't.
    old_disabled, Promiscuous.disabled = Promiscuous.disabled?, false
    old_current, self.current = self.current, nil
    yield
  rescue Exception => e
    $promiscuous_last_exception = e if e.is_a? Promiscuous::Error::Base
    pretty_print_exception(e)
    raise e
  ensure
    self.current = old_current
    Promiscuous.disabled = old_disabled
  end

  def self.pretty_print_exception(e)
    return if $promiscuous_pretty_print_exception_once == :disable || ENV['RAILS_ENV'] == 'production'
    return if e.is_a?(SystemExit)

    e = e.original_exception if defined?(ActionView::Template::Error) && e.is_a?(ActionView::Template::Error)

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

    if $cucumber_extra
      STDERR.puts "\e[0;#{36}m+---[ Cucumber ]--------------------------------------------------------------------------------------\e[0m"
      STDERR.puts "\e[0;#{36}m|"
      $cucumber_extra.each_with_index do |line, i|
        line = line.gsub(/([^:]*: )(.*)$/, "\\1\e[1;36m\\2")
        STDERR.puts "\e[0;#{36}m| \e[0;36m#{line}\e[0m"
        STDERR.puts "\e[0;#{36}m|" if i.zero?
      end
      STDERR.puts "\e[0;#{36}m|"
    end

    STDERR.puts "\e[0;#{36}m\\------------------------------------------------------------------------------------------------------\e[0m"
    STDERR.puts
    $promiscuous_pretty_print_exception_once = :disable if $promiscuous_pretty_print_exception_once
  end
end
