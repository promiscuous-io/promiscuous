class Promiscuous::Subscriber::Base
  include Promiscuous::Common::Options

  attr_accessor :options

  def initialize(options)
    self.options = options
  end

  def payload
    options[:payload]
  end
  alias :instance :payload

  def process
  end

  def should_update_parent?
    true
  end

  def subscribe_options
    self.class.options
  end

  def self.subscribe(options)
    load_options(options)
  end
end
