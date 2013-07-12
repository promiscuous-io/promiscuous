module Promiscuous::Publisher::Model::Mongoid
  extend ActiveSupport::Concern
  include Promiscuous::Publisher::Model::Base

  mattr_accessor :collection_mapping
  self.collection_mapping = {}

  # We hook at the database driver level
  require 'promiscuous/publisher/operation/mongoid'
  included do
    # Important for the query hooks (see ../operation/mongoid.rb)
    # We want the root class when we do a collection name lookup

    root_class = self.collection.name.singularize.camelize.constantize
    unless self == root_class
      raise "Please include Promiscuous::Publisher in #{root_class} first (the root class)"
    end

    Promiscuous::Publisher::Model::Mongoid.collection_mapping[self.collection.name] = self
  end

  class PromiscuousMethods
    include Promiscuous::Publisher::Model::Base::PromiscuousMethodsBase

    def sync(options={}, &block)
      raise "Use promiscuous.sync on the parent instance" if @instance.embedded?
      super
    end

    def attribute(attr)
      value = super
      if value.is_a?(Array) &&
         value.respond_to?(:ancestors) &&
         value.ancestors.any? { |a| a == Promiscuous::Publisher::Model::Mongoid }
        value = {:__amqp__ => '__promiscuous__/embedded_many',
                 :payload  => value.map(&:promiscuous).map(&:payload)}
      end
      value
    end
  end

  module ClassMethods
    # TODO DRY this up with the publisher side
    def publish(*args, &block)
      super
      return unless block

      begin
        @in_publish_block = true
        block.call
      ensure
        @in_publish_block = false
      end
    end

    def self.publish_on(method, options={})
      define_method(method) do |name, *args, &block|
        super(name, *args, &block)
        if @in_publish_block
          name = args.last[:as] if args.last.is_a?(Hash) && args.last[:as]
          publish(name)
        end
      end
    end

    publish_on :field
    publish_on :embeds_one
    publish_on :embeds_many

    def promiscuous_collection_name
      self.collection.name
    end

    def get_operation_class_for(operation)
      if operation == :create
        Moped::PromiscuousCollectionWrapper::PromiscuousCollectionOperation
      else
        Moped::PromiscuousQueryWrapper::PromiscuousQueryOperation
      end
    end
  end
end
