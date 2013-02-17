module Promiscuous::Publisher::Model::Base
  extend ActiveSupport::Concern

  included do
    class_attribute :publish_to, :published_attrs
    self.published_attrs = []

    Promiscuous::Publisher::Model.publishers << self
  end

  module PromiscuousMethodsBase
    def initialize(instance)
      @instance = instance
    end

    def sync(options={}, &block)
      options = options.dup
      options[:instance] = @instance
      options[:operation] ||= :update
      Promiscuous::Publisher::Operation.new(options).commit(&block)
    end

    def payload(options={})
      msg = {}
      msg[:__amqp__]  = @instance.class.publish_to
      msg[:type]      = @instance.class.publish_as # for backward compatibility
      msg[:ancestors] = @instance.class.ancestors.select { |a| a < Promiscuous::Publisher::Model::Base }.map(&:publish_as)
      msg[:id]        = @instance.id.to_s
      msg[:payload]   = self.attributes     if options[:operation].in?([nil, :create, :update])
      msg[:operation] = options[:operation] if options[:operation]
      msg[:version]   = options[:version]   if options[:version]
      msg
    end

    def attributes
      Hash[@instance.class.published_attrs.map { |attr| [attr, self.attribute(attr)] }]
    end

    def attribute(attr)
      value = @instance.__send__(attr)
      value = value.promiscuous.payload if value.respond_to?(:promiscuous)
      value
    end

    def publish(options={})
      payload = self.payload(options)
      Promiscuous::AMQP.publish(:key => payload[:__amqp__], :payload => payload.to_json)
    rescue Exception => e
      raise Promiscuous::Error::Publisher.new(e, :instance => @instance, :payload => payload, :out_of_sync => true)
    end
  end

  class PromiscuousMethods
    include Promiscuous::Publisher::Model::Base::PromiscuousMethodsBase
  end

  def promiscuous
    # XXX Not thread safe, but sharing models between threads is a bad idea to begin with
    @promiscuous ||= self.class.const_get(:PromiscuousMethods).new(self)
  end

  module ClassMethods
    def publish(*args, &block)
      options    = args.extract_options!
      attributes = args

      # TODO reject invalid options

      if attributes.present? && self.publish_to && options[:to] && self.publish_to != options[:to]
        raise 'versionned publishing is not supported yet'
      end
      self.publish_to ||= options[:to] || "#{Promiscuous::Config.app}/#{self.name.underscore}"
      @publish_as = options[:as].to_s if options[:as]

      ([self] + descendants).each { |klass| klass.published_attrs |= attributes }
    end

    def publish_as
      @publish_as || name
    end

    def inherited(subclass)
      super
      subclass.published_attrs = self.published_attrs.dup
    end
  end
end
