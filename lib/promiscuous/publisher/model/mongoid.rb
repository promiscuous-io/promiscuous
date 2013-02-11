module Promiscuous::Publisher::Model::Mongoid
  extend ActiveSupport::Concern
  include Promiscuous::Publisher::Model

  def promiscuous_sync(options={}, &block)
    raise "Use promiscuous_sync on the parent instance" if self.embedded?

    options = options.dup
    options[:operation]  ||= :update
    options[:collection] = collection.name
    options[:selector]   = atomic_selector
    Promiscuous::Publisher::Model::Mongoid::Operation.new(options).commit(&block)
  end

  def __promiscuous_attribute(attr)
    value = super
    if value.is_a?(Array) && value.ancestors.any? { |a| a == Promiscuous::Publisher::Model }
      value = { :__amqp__ => '__promiscuous__/embedded_many',
                :payload  => value.map(&:to_promiscuous) }
    end
    value
  end

  class Operation < Promiscuous::Publisher::Operation
    attr_accessor :collection, :selector, :document
    def initialize(options={})
      super
      self.collection = options[:collection]
      self.selector   = options[:selector]
      self.document   = options[:document]
    end

    def model
      @model ||= document.try(:[], '_type').try(:constantize) ||
                 collection.singularize.camelize.constantize
    rescue NameError
    end

    def fetch_instance(id=nil)
      return model.find(id) if id

      if operation == :create
        # FIXME we need to call demongoize or something
        model.new(document, :without_protection => true)
      else
        # FIXME respect the original ordering
        model.with(:consistency => :strong).where(selector).first
      end
    end

    def commit(&db_operation)
      @instance = fetch_instance()
      return yield unless @instance.is_a?(Promiscuous::Publisher::Model::Mongoid)
      super
    end
  end

  def self.check_mongoid_version
    unless Gem.loaded_specs['mongoid'].version >= Gem::Version.new('3.0.19')
      raise "mongoid > 3.0.19 please"
    end

    unless Gem.loaded_specs['moped'].version >= Gem::Version.new('1.3.2')
      raise "moped > 1.3.2 please"
    end
  end

  def self.hook_mongoid
    Moped::Collection.class_eval do
      alias_method :insert_orig, :insert
      def insert(documents, flags=nil)
        documents = [documents] unless documents.is_a?(Array)
        documents.each do |doc|
          Promiscuous::Publisher::Model::Mongoid::Operation.new(
            :collection => self.name,
            :document   => doc,
            :operation  => :create
          ).commit do
            insert_orig(doc, flags)
          end
        end
      end
    end

    Moped::Query.class_eval do
      alias_method :update_orig, :update
      def update(change, flags=nil)
        if flags && flags.include?(:multi)
          raise "Promiscuous: Do not use multi updates, update each instance separately"
        end

        Promiscuous::Publisher::Model::Mongoid::Operation.new(
          :collection => collection.name,
          :selector   => selector,
          :operation  => :update
        ).commit do |id|
          # TODO FIXME selector = {:id => id} if id
          update_orig(change, flags)
        end
      end

      alias_method :modify_orig, :modify
      def modify(change, options={})
        Promiscuous::Publisher::Model::Mongoid::Operation.new(
          :collection => collection.name,
          :selector   => selector,
          :operation  => :update
        ).commit do |id|
          # TODO FIXME selector = {:id => id} if id
          modify_orig(change, options)
        end
      end

      alias_method :remove_orig, :remove
      def remove
        Promiscuous::Publisher::Model::Mongoid::Operation.new(
          :collection => collection.name,
          :selector   => selector,
          :operation  => :destroy
        ).commit do |id|
          # TODO FIXME selector = {:id => id} if id
          remove_orig
        end
      end

      alias_method :remove_all_orig, :remove_all
      def remove_all
        raise "Promiscuous: Do not use delete_all, use destroy_all"
      end
    end
  end

  check_mongoid_version
  hook_mongoid
end
