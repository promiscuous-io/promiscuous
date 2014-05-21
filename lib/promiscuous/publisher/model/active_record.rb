module Promiscuous::Publisher::Model::ActiveRecord
  extend ActiveSupport::Concern
  include Promiscuous::Publisher::Model::Base

  require 'promiscuous/publisher/operation/active_record'

  module ClassMethods
    def __promiscuous_missing_record_exception
      ActiveRecord::RecordNotFound
    end

    def belongs_to(*args, &block)
      super.tap do |association|
        fk = if association.is_a?(Hash)
               association.values.first.foreign_key  # ActiveRecord 4x
             else
               association.foreign_key  # ActiveRecord 3x
             end
        publish(fk) if self.in_publish_block?
      end
    end
  end
end
