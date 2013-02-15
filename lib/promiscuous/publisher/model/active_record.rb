module Promiscuous::Publisher::Model::ActiveRecord
  extend ActiveSupport::Concern
  include Promiscuous::Publisher::Model::Base

  # TODO FIXME This needs some serious work. We need to hook deeper.

  included do
    around_create  { |&block| promiscuous_sync(:operation => :create,  &block) }
    around_update  { |&block| promiscuous_sync(:operation => :update,  &block) }
    around_destroy { |&block| promiscuous_sync(:operation => :destroy, &block) }
  end
end
