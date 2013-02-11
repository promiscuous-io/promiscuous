module Promiscuous::Publisher::Model
  extend Promiscuous::Autoload
  autoload :ActiveRecord, :Ephemeral, :Mock, :Mongoid

  extend ActiveSupport::Concern

  included do
    class_attribute :publish_to
    class << self; attr_accessor :published_fields; end
    self.published_fields = []
  end

  def promiscuous_sync(options={}, &block)
    options = options.dup
    options[:instance] = self
    options[:operation] ||= :update
    Promiscuous::Publisher::Operation.new(options).commit(&block)
  end

  def to_promiscuous(options={})
    msg = {}
    msg[:__amqp__]  = self.class.publish_to
    msg[:type]      = self.class.name # for backward compatibility
    msg[:ancestors] = self.class.ancestors.select { |a| a < Promiscuous::Publisher::Model }.map(&:name)
    msg[:id]        = self.id.to_s
    msg[:payload]   = self.__promiscuous_attributes if options[:operation].in?([nil, :create, :update])
    msg[:operation] = options[:operation]           if options[:operation]
    msg[:version]   = options[:version]             if options[:version]
    msg
  end

  def __promiscuous_attributes
    Hash[self.class.published_fields.map { |field| [field, self.__promiscuous_attribute(field)] }]
  end

  def __promiscuous_attribute(attr)
    value = __send__(attr)
    value = value.to_promiscuous if value.respond_to?(:to_promiscuous)
    value
  end

  def __promiscuous_publish(options={})
    payload = self.to_promiscuous(options)
    Promiscuous::AMQP.publish(:key => payload[:__amqp__], :payload => payload.to_json)
  rescue Exception => e
    raise Promiscuous::Error::Publisher.new(e, :instance => self, :payload => payload, :out_of_sync => true)
  end

  module ClassMethods
    def publish(*args)
      options    = args.extract_options!
      attributes = args

      if self.publish_to && options[:to] && self.publish_to != options[:to]
        raise 'versionned publishing is not supported yet'
      end
      self.publish_to ||= options[:to] || "#{Promiscuous::Config.app}/#{self.name.underscore}"

      ([self] + descendants).each { |klass| klass.published_fields |= attributes }
    end

    def inherited(subclass)
      super
      subclass.published_fields = self.published_fields.dup
    end
  end
end
