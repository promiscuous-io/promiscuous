module Promiscuous::Subscriber::Model::Observer
  extend ActiveSupport::Concern
  include Promiscuous::Subscriber::Model::Base

  included do
    extend ActiveModel::Callbacks
    attr_accessor :id
    define_model_callbacks :save, :create, :update, :destroy, :only => :after
  end

  def __promiscuous_eventual_consistency_update(operation)
    true
  end

  def __promiscuous_update(payload, options={})
    super
    case payload.operation
    when :create
      run_callbacks :create
      run_callbacks :save
    when :update
      run_callbacks :update
      run_callbacks :save
    when :destroy
      run_callbacks :destroy
    else
      raise "Unknown operation #{payload.operation}"
    end
  end

  def destroy
    run_callbacks :destroy
  end

  def save!
  end

  module ClassMethods
    def subscribe(*args)
      super
      subscribed_attrs.each do |attr|
        attr_accessor attr
      end
    end

    def __promiscuous_fetch_new(id)
      new.tap { |o| o.id = id }
    end
    alias __promiscuous_fetch_existing __promiscuous_fetch_new

    def __promiscuous_duplicate_key_exception?(e)
      false
    end
  end
end
