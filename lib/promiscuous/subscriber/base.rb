class Promiscuous::Subscriber::Base
  attr_accessor :options
  class_attribute :options

  def initialize(options)
    self.options = options
  end

  def payload
    options[:payload]
  end
  alias :instance :payload

  def process
  end

  def subscribe_options
    self.class.options
  end

  def self.subscribe(options)
    self.options = options
  end

  def self.use_option(attr, options={})
    as = options[:as].nil? ? attr : options[:as]
    define_method(as) do
      self.class.options[attr]
    end
  end
end
