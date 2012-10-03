module Promiscuous::Common::Worker
  extend ActiveSupport::Concern

  def initialize
    self.stop = false
  end

  def unit_of_work
    if defined?(Mongoid)
      Mongoid.unit_of_work { yield }
    else
      yield
    end
  end

  included { attr_accessor :stop }
end
