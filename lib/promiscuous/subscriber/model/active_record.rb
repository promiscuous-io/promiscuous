module Promiscuous::Subscriber::Model::ActiveRecord
  extend ActiveSupport::Concern
  include Promiscuous::Subscriber::Model::Base

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
      yield
      ActiveRecord::Base.clear_active_connections!
    end
  end

  class << self
    def check_migrations
      subscribers = ActiveRecord::Base.descendants.select do |x|
        x.include?(self)
      end

      subscribers.each do |subscriber|
        next if subscriber.columns.collect(&:name).include?("_v")

        puts <<-help
#{subscriber} must include a _v column.  Create the following migration:
  subscriber :#{subscriber.table_name} do |t|
    t.integer :_v, :limit => 8, :default => 1
  end
        help
      end
    end
  end
end
