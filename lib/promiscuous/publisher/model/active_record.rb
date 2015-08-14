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

  class << self
    def check_migrations
      publishers = ActiveRecord::Base.descendants.select do |x|
        x.include?(self)
      end

      publishers.each do |publisher|
        next if publisher.columns.collect(&:name).include?("_v")

        puts <<-help
#{publisher} must include a _v column.  Create the following migration:
  publisher :#{publisher.table_name} do |t|
    t.integer :_v, :limit => 8, :default => 1
  end
        help
      end
    end
  end
end
