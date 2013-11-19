module Promiscuous::Publisher::Model::Ephemeral
  extend ActiveSupport::Concern
  include Promiscuous::Publisher::Model::Base

  attr_accessor :id, :new_record, :destroyed

  module PromiscuousMethodsEphemeral
    def attribute(attr)
      value = super
      if value.is_a?(Array) &&
         value.first.is_a?(Promiscuous::Publisher::Model::Ephemeral)
        value = {:types => ['Promiscuous::EmbeddedDocs'],
                 :attributes => value.map(&:promiscuous).map(&:payload)}
      end
      value
    end
  end

  class PromiscuousMethods
    include Promiscuous::Publisher::Model::Base::PromiscuousMethodsBase
    include Promiscuous::Publisher::Model::Ephemeral::PromiscuousMethodsEphemeral
  end

  def initialize(attrs={})
    self.id ||= 'none'
    self.new_record = true
    self.destroyed = false
    attrs.each { |attr, value| __send__("#{attr}=", value) }
  end

  def save
    operation = :create
    operation = :update  unless self.new_record
    operation = :destroy if     self.destroyed

    save_operation(operation)

    self.new_record = false
    true
  end
  alias :save! :save

  def save_operation(operation)
    Promiscuous::Publisher::Operation::Ephemeral.new(:instance => self, :operation => operation).execute
  end

  def update_attributes(attrs)
    attrs.each { |attr, value| __send__("#{attr}=", value) }
    save
  end
  alias :update_attributes! :update_attributes

  def destroy
    self.destroyed = true
    save
  end

  def attributes
    Hash[self.class.published_attrs.map { |attr| [attr, __send__(attr)] }]
  end

  module ClassMethods
    def publish(*args)
      super
      published_attrs.each do |attr|
        # TODO do not overwrite existing methods
        attr_accessor attr
      end
    end

    def create(attributes)
      new(attributes).tap { |m| m.save }
    end
  end
end
