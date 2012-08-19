class Promiscuous::Publisher::Base
  attr_accessor :options
  class_attribute :options, :published
  self.options = {}

  def initialize(options)
    self.options = options
  end

  def instance
    options[:instance]
  end

  def self.publish(options)
    self.options = self.options.merge(options)
    self.published = true
  end

  def self.use_option(attr)
    define_method(attr) do
      self.class.options[attr]
    end
  end
end
