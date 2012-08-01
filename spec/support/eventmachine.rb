require 'eventmachine'
require 'em-synchrony'

RSpec::Core::Example.class_eval do
  alias run_without_em run

  def run(example_group_instance, reporter)
    ret = nil
    EM.synchrony do
      ret = run_without_em example_group_instance, reporter
      EM.stop
    end
    ret
  end
end

module AsyncHelper
  def eventually(options = {})
    timeout = options[:timeout] || 2
    interval = options[:interval] || 0.1
    time_limit = Time.now + timeout
    loop do
      begin
        yield
      rescue => error
      end
      return if error.nil?
      raise error if Time.now >= time_limit
      EM::Synchrony.sleep interval
    end
  end
end
