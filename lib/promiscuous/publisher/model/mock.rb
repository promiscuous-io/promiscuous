module Promiscuous::Publisher::Model::Mock
  extend ActiveSupport::Concern
  include Promiscuous::Publisher::Model::Ephemeral

  included do
    class_attribute :mock_options
    self.mock_options = {}
  end

  def initialize(attrs={})
    self.id = __get_new_id
    super
  end

  def __get_new_id
    if self.class.mock_options[:id] == :bson
      BSON::ObjectId.new
    else
      # XXX Not thread safe
      @@next_id ||= 1
      @@next_id += 1
    end
  end

  def save_operation(operation)
    payload = nil

    op = Promiscuous::Publisher::Operation::Ephemeral.new(:instance => self, :operation => operation)
    # TODO FIX the mocks to populate app name, also we need to hook before the
    # json dump.
    batch = op.create_transport_batch([op])

    Promiscuous::Subscriber::Message.new(batch.payload).process
  end

  module ClassMethods
    def publish_as
      # The mocks are in the publisher's namespace, so we need to remove that.
      @publish_as ||= ($2 if self.name =~ /^(.+)::Publishers::(.+)$/)
    end

    def mock(options={})
      # careful, all subclasses will be touched
      self.mock_options.merge!(options)
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
