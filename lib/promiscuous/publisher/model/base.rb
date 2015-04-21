module Promiscuous::Publisher::Model::Base
  extend ActiveSupport::Concern

  included do
    class_attribute :published_attrs
    cattr_accessor  :published_db_fields # There is one on each root class, none on the subclasses
    self.published_attrs = []
    self.published_db_fields = []
    Promiscuous::Publisher::Model.publishers[self.promiscuous_collection_name] = self
  end

  module PromiscuousMethodsBase
    def initialize(instance)
      @instance = instance
    end

    def payload(options={})
      msg = {}
      msg[:types] = types
      msg[:id]    = @instance.id.to_s
      unless options[:with_attributes] == false
        # promiscuous_payload is useful to implement relays
        msg[:attributes] = @instance.respond_to?(:promiscuous_payload) ? @instance.promiscuous_payload :
                                                                         self.attributes
      end
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

    def id
      @instance.id
    end

    def sync(target)
      Promiscuous.ensure_connected

      raise "Model cannot be dirty (have changes) when syncing" if @instance.changed?
      raise "Model has to be reloaded if it was saved" if @instance.previous_changes.present?

      # XXX Temporary while until we sync on seperate topics
      topic = target == Promiscuous::Config.sync_all_routing ? Promiscuous::Config.app : target

      # We can use the ephemeral because both are mongoid and ephemerals are atomic operations.
      Promiscuous::Publisher::Operation::Ephemeral.new(:instance => @instance,
                                                       :operation_name => :update,
                                                       :routing => target,
                                                       :topic   => topic,
                                                       :exchange => Promiscuous::Config.sync_exchange).execute
    end

    def types
      @instance.class.ancestors.select { |a| a < Promiscuous::Publisher::Model::Base }.map(&:publish_as)
    end

    def key
      [Promiscuous::Config.app,types.first,id].join('/')
    end
  end

  class PromiscuousMethods
    include Promiscuous::Publisher::Model::Base::PromiscuousMethodsBase
  end

  def promiscuous
    # XXX Not thread safe
    @promiscuous ||= self.class.const_get(:PromiscuousMethods).new(self)
  end

  module ClassMethods
    # all methods are virtual

    def publish(*args, &block)
      options    = args.extract_options!
      attributes = args.map(&:to_sym)

      # TODO reject invalid options

      @publish_as = options[:as].to_s if options[:as]

      ([self] + descendants).each do |klass|
        # When the user passes :use => [:f1, :f2] for example, operation/mongoid.rb
        # can track f1 and f2 as fields important for the publishing.
        # It's important for virtual attributes. The published_db_fields is global
        # for the entire subclass tree.
        klass.published_db_fields |= [options[:use]].flatten.map(&:to_sym) if options[:use]
        klass.published_db_fields |= attributes # aliased fields are resolved later
        klass.published_attrs     |= attributes
      end


      begin
        @in_publish_block = @in_publish_block.to_i + 1
        block.call if block
      ensure
        @in_publish_block -= 1
      end
    end

    def in_publish_block?
      @in_publish_block.to_i > 0
    end

    def promiscuous_collection_name
      self.name.pluralize.underscore
    end

    def get_operation_class_for(operation)
      Promiscuous::Publisher::Operation::Base
    end

    def publish_as
      @publish_as || name
    end

    def inherited(subclass)
      super
      subclass.published_attrs = self.published_attrs.dup
      # no copy for published_db_fields
    end
  end
end
