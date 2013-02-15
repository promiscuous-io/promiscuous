module Promiscuous::Subscriber::Model::Observer
  extend ActiveSupport::Concern
  include Promiscuous::Subscriber::Model::Base

  included do
    extend ActiveModel::Callbacks
    attr_accessor :id
    define_model_callbacks :create, :update, :destroy, :only => :after
  end

  def __promiscuous_update(payload, options={})
    super
    run_callbacks payload.operation
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
        # TODO do not overwrite existing methods
        attr_accessor attr
      end
    end

    def __promiscuous_fetch_new(id)
      new.tap { |o| o.id = id }
    end
    alias __promiscuous_fetch_existing __promiscuous_fetch_new
  end
end
