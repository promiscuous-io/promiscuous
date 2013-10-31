require 'ruby-progressbar'

module Promiscuous::Publisher::Bootstrap::Status
  def self.reset
    redis.del(key)
  end

  def self.total(count)
    redis.hincrby(key, 'total', count)
  end

  def self.inc
    redis.hincrby(key, 'processed', 1)
  end

  def self.monitor
    total ||= redis.hget(key, 'total').to_i
    processed = 0
    exit_now = false

    %w(SIGTERM SIGINT).each { |signal| Signal.trap(signal) { exit_now = true  } }
    bar = ProgressBar.create(:format => '%t |%b>%i| %c/%C %e', :title => "Bootstrapping", :total => total)
    while processed < total
      processed = redis.hget(key, 'processed').to_i
      bar.progress = processed
      sleep 1
      break if exit_now
    end
  end

  private

  def self.key
    Promiscuous::Key.new(:pub).join('bootstrap:counter')
  end

  def self.redis
    Promiscuous::Redis.master.nodes.first
  end
end
