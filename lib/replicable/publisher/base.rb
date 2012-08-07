class Replicable::Publisher::Base
  attr_accessor :options
  class_attribute :options

  def initialize(options)
    self.options = options
  end

  def instance
    options[:instance]
  end

  def self.publish(options)
    self.options = options
  end

  def self.use_option(attr)
    define_method(attr) do
      self.class.options[attr]
    end
  end
end
