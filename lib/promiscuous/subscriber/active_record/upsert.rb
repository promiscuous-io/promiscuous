module Promiscuous::Subscriber::ActiveRecord::Upsert
  extend ActiveSupport::Concern

  def fetch
    begin
      super
    rescue ActiveRecord::RecordNotFound
      Promiscuous.warn "[receive] upserting #{payload}"
      klass.new.tap { |o| o.id = id }
    end
  end
end
