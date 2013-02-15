module Promiscuous::Subscriber::Model::ActiveRecord
  extend ActiveSupport::Concern
  include Promiscuous::Subscriber::Model::Base

  module ClassMethods
    def __promiscuous_missing_record_exception
      ActiveRecord::RecordNotFound
    end
  end
end
