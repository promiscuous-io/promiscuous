module Promiscuous::Worker
  mattr_accessor :workers
  self.workers = []

  def self.replicate(options={})
    publish   = options[:only].nil? || options[:only] == :publish
    subscribe = options[:only].nil? || options[:only] == :subscribe

    self.workers << Promiscuous::Publisher::Worker.new(options) if publish
    self.workers << Promiscuous::Subscriber::Worker.new(options) if subscribe
    self.workers.each { |w| w.replicate }
  end

  def self.stop
    self.workers.each { |w| w.stop = true }
    self.workers.clear
  end
end
