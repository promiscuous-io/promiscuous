module Promiscuous::Subscriber::Model::ActiveRecord
  extend ActiveSupport::Concern
  include Promiscuous::Subscriber::Model::Base

  included do
    if !self.columns.collect(&:name).include?("_v")
      raise <<-help
      #{self} must include a _v column.  Create the following migration:
        change_table :#{self.table_name} do |t|
          t.integer :_v, :limit => 8
        end
      help
    end
  end

  module ClassMethods
    def __promiscuous_missing_record_exception
      ActiveRecord::RecordNotFound
    end

    def __promiscuous_duplicate_key_exception?(e)
      # TODO Ensure that it's on the pk
      e.is_a?(ActiveRecord::RecordNotUnique)
    end

    def __promiscuous_fetch_existing(id)
      key = subscribe_foreign_key
      if promiscuous_root_class.respond_to?("find_by_#{key}!")
        promiscuous_root_class.__send__("find_by_#{key}!", id)
      elsif respond_to?("find_by")
        promiscuous_root_class.find_by(key => id)
      end
    end

    def __promiscuous_with_pooled_connection
      ActiveRecord::Base.connection_pool.with_connection { yield }
    end
  end
end
