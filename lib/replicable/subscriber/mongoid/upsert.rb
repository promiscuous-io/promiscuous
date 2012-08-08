module Replicable::Subscriber::Mongoid::Upsert
  extend ActiveSupport::Concern

  def fetch
    begin
      super
    rescue Mongoid::Errors::DocumentNotFound
      klass.new.tap { |o| o.id = id }
    end
  end
end
