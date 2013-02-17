module Promiscuous::Publisher::Model::ActiveRecord
  extend ActiveSupport::Concern
  include Promiscuous::Publisher::Model::Base

  # TODO FIXME This needs some serious work. We need to hook deeper.

  included do
    around_create  { |&block| promiscuous.sync(:operation => :create,  &block) }
    around_update  { |&block| promiscuous.sync(:operation => :update,  &block) }
    around_destroy { |&block| promiscuous.sync(:operation => :destroy, &block) }
  end

  module ClassMethods
    def __promiscuous_missing_record_exception
      ActiveRecord::RecordNotFound
    end
  end
end
