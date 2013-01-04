module Promiscuous::Worker
  mattr_accessor :workers
  self.workers = []

  def self.replicate(options={})
    options[:action] ||= [:publish, :subscribe]
    actions = [options[:action]].flatten

    self.workers << Promiscuous::Publisher::Worker.new(options)  if :publish.in? actions
    self.workers << Promiscuous::Subscriber::Worker.new(options) if :subscribe.in? actions
    self.workers.each { |w| w.replicate }
  end

  def self.stop
    self.workers.each { |w| w.stop = true }
    self.workers.clear
  end

  def self.pause
    self.workers.each { |w| w.stop = true }
  end

  def self.resume
    self.workers.each { |w| w.stop = false }
  end
end
