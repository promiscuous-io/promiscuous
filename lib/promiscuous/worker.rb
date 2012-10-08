module Promiscuous::Worker
  mattr_accessor :workers
  self.workers = []

  def self.replicate
    self.workers << Promiscuous::Subscriber::Worker.new
    self.workers.each { |w| w.replicate }
  end

  def self.stop
    self.workers.each { |w| w.stop = true }
    self.workers.clear
  end
end
