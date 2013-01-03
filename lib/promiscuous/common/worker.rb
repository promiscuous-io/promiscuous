module Promiscuous::Common::Worker
  extend ActiveSupport::Concern

  def initialize(options={})
    self.options = options
    self.stop = false
  end

  def unit_of_work(type)
    if defined?(Mongoid)
      Mongoid.unit_of_work { yield }
    else
      yield
    end
  end

  def bareback?
    !!options[:bareback]
  end

  included { attr_accessor :stop, :options }
end
