class Promiscuous::Publisher::Base
  include Promiscuous::Common::Options

  cattr_accessor :published
  attr_accessor :options

  def initialize(options)
    self.options = options
  end

  def instance
    options[:instance]
  end

  def self.publish(options)
    load_options(options)
    self.published = true
  end
end
