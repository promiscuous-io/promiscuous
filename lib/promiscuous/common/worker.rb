module Promiscuous::Common::Worker
  extend ActiveSupport::Concern

  def initialize(options={})
    self.options = options
    self.stop = false
  end

  def unit_of_work
    if defined?(Mongoid)
      Mongoid.unit_of_work { yield }
    else
      yield
    end
  end

  included { attr_accessor :stop, :options }
end
