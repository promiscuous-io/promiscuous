module Promiscuous::Worker
  mattr_accessor :workers
  self.workers = []

  def self.replicate(options={})
    self.workers << Promiscuous::Subscriber::Worker.new(options).tap { |w| w.start }
  end

  def self.kill
    stop
    # TODO FIXME We should wait for them to be idle
    workers.clear
  end

  def self.stop
    workers.each(&:stop)
  end

  def self.start
    workers.each(&:start)
  end
end
