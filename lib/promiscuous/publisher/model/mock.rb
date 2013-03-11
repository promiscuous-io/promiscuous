module Promiscuous::Publisher::Model::Mock
  extend ActiveSupport::Concern
  include Promiscuous::Publisher::Model::Ephemeral

  included { class_attribute :mock_options }

  def initialize(attrs={})
    self.id = __get_new_id
    super
  end

  def __get_new_id
    if self.class.mock_options.try(:[], :id) == :bson
      BSON::ObjectId.new
    else
      # XXX Not thread safe
      @@next_id ||= 1
      @@next_id += 1
    end
  end

  class PromiscuousMethods
    include Promiscuous::Publisher::Model::Base::PromiscuousMethodsBase
    include Promiscuous::Publisher::Model::Ephemeral::PromiscuousMethodsEphemeral

    def sync(options={}, &block)
      payload = self.payload
      payload[:operation] = options[:operation] || :update
      Promiscuous::Subscriber::Worker::Message.new(nil, payload.to_json).process
    end
  end

  module ClassMethods
    def publish_as
      # The mocks are in the publisher's namespace, so we need to remove that.
      @publish_as ||= ($2 if self.name =~ /^(.+)::Publishers::(.+)$/)
    end

    def mock(options={})
      self.mock_options = options
    end

    def publish(*args, &block)
      super

      args.extract_options!
      attributes = args
      attr_accessor(*attributes)

      # Hacks for associations on the factory
      associations = attributes.map { |attr| $1 if attr =~ /^(.*)_id$/ }.compact
      associations.each do |attr|
        attr_accessor(attr)
        define_method("#{attr}=") do |value|
          instance_variable_set("@#{attr}", value)
          instance_variable_set("@#{attr}_id", value.nil? ? value : value.id)
        end
      end
    end
  end
end
