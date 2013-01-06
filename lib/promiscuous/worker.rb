module Promiscuous::Worker
  mattr_accessor :workers
  self.workers = []

  def self.replicate(options={})
    options[:action] ||= [:publish, :subscribe]
    actions = [options[:action]].flatten

    self.workers <<  Promiscuous::Publisher::Worker.new(options).tap { |w| w.resume } if :publish.in? actions
    self.workers << Promiscuous::Subscriber::Worker.new(options).tap { |w| w.resume } if :subscribe.in? actions
  end

  def self.kill
    stop
    # TODO FIXME We should wait for them to be idle
    workers.clear
  end

  def self.stop
    workers.each(&:stop)
  end

  def self.resume
    workers.each(&:resume)
  end
end
