module Promiscuous::Publisher::Model::Mongoid
  extend ActiveSupport::Concern

  class Commit
    attr_accessor :collection, :selector, :document, :operation
    def initialize(options={})
      self.collection = options[:collection]
      self.selector   = options[:selector]
      self.document   = options[:document]
      self.operation  = options[:operation]
    end

    def klass
      @klass ||= (document['_type'].try(:constantize) if document) ||
                 collection.singularize.camelize.constantize
    end

    def fetch
      case operation
      when :create  then klass.new(document, :without_protection => true)
      when :update  then klass.where(selector).first
      when :destroy then klass.where(selector).first

      end.tap do |doc|
        if doc.nil?
          inner = Mongoid::Errors::DocumentNotFound.new(klass, selector)
          raise Promiscuous::Error::Publisher.new(inner)
        end
      end
    end

    def commit(&block)
      return block.call if klass.nil?
      instance = fetch
      return block.call unless instance.class.respond_to?(:promiscuous_publisher)

      publisher = instance.class.promiscuous_publisher
      publisher.new(:operation  => operation,
                    :instance   => instance,
                    :fetch_proc => method(:fetch)).commit(&block)
    end
  end

  def self.hook_mongoid
    Moped::Collection.class_eval do
      alias_method :insert_orig, :insert
      def insert(documents, flags=nil)
        documents = [documents] unless documents.is_a?(Array)
        documents.each do |doc|
          Promiscuous::Publisher::Model::Mongoid::Commit.new(
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
        Promiscuous::Publisher::Model::Mongoid::Commit.new(
          :collection => collection.name,
          :selector   => selector,
          :operation  => :update
        ).commit do
          update_orig(change, flags)
        end
      end

      alias_method :modify_orig, :modify
      def modify(change, options={})
        Promiscuous::Publisher::Model::Mongoid::Commit.new(
          :collection => collection.name,
          :selector   => selector,
          :operation  => :update
        ).commit do
          modify_orig(change, options)
        end
      end

      alias_method :remove_orig, :remove
      def remove
        Promiscuous::Publisher::Model::Mongoid::Commit.new(
          :collection => collection.name,
          :selector   => selector,
          :operation  => :destroy
        ).commit do
          remove_orig
        end
      end
    end
  end
  hook_mongoid
end
