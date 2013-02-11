module Promiscuous::Publisher::Model::Ephemeral
  extend ActiveSupport::Concern
  include Promiscuous::Publisher::Model

  attr_accessor :id, :new_record, :destroyed

  def initialize(attrs)
    self.id = 1
    self.new_record = true
    self.destroyed = false
    attrs.each { |attr, value| __send__("#{attr}=", value) }
  end

  def save
    operation = :create
    operation = :update  unless self.new_record
    operation = :destroy if     self.destroyed
    promiscuous_sync(:operation => operation)
    self.new_record = false
    true
  end
  alias :save! :save

  def update_attributes(attrs)
    attrs.each { |attr, value| __send__("#{attr}=", value) }
    save
  end
  alias :update_attributes! :update_attributes

  def destroy
    self.destroyed = true
    save
  end

  module ClassMethods
    def create(attributes)
      new(attributes).tap { |m| m.save }
    end
  end
end
