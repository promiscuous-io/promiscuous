module Promiscuous::Subscriber::Mongoid::Upsert
  extend ActiveSupport::Concern

  def fetch
    begin
      super
    rescue Mongoid::Errors::DocumentNotFound
      Promiscuous.warn "[receive] upserting #{payload}"
      klass.new.tap { |o| o.id = id }
    end
  end
end
