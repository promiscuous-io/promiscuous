class Promiscuous::Subscriber::Base
  attr_accessor :options
  class_attribute :options, :options_mappings, :instance_reader => false, :instance_writer => false

  self.options = self.options_mappings = {}

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
    options.each do |attr, value|
      attr_alias = self.options_mappings[attr]
      self.__send__("#{attr_alias}=", value) if attr_alias
    end
  end

  def self.inherited(subclass)
    super
    subclass.options = self.options.dup
  end

  def self.use_option(attr, options={})
    attr_alias = options[:as].nil? ? attr : options[:as]
    self.options_mappings[attr] = attr_alias

    # We need to let all the modules overload these methods, which is
    # why we are injecting at the base level.
    Promiscuous::Subscriber::Base.singleton_class.class_eval do
      define_method("#{attr_alias}")  { self.options[attr] }
      define_method("#{attr_alias}=") { |value| self.options[attr] = value }
    end
  end
end
