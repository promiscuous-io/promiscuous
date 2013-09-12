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

    if self.superclass.include?(Mongoid::Document)
      raise "Please include Promiscuous::Publisher in the root class of #{self}"
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
        value = {:types => ['Promiscuous::EmbeddedDocs'],
                 :attributes => value.map(&:promiscuous).map(&:payload)}
      end
      value
    end
  end

  module ClassMethods
    # TODO DRY this up with the publisher side
    def self.publish_on(method, options={})
      define_method(method) do |name, *args, &block|
        super(name, *args, &block)
        if self.in_publish_block?
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
