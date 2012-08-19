class Promiscuous::Publisher::Lint::Base
  attr_accessor :options

  def initialize(options)
    self.options = options
  end

  def publisher_instance
    @publisher_instance ||= publisher.new({})
  end

  def lint
  end

  def self.use_option(attr)
    define_method(attr) do
      self.options[attr]
    end
  end

  use_option(:publisher)
end
