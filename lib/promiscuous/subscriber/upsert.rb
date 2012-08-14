module Promiscuous::Subscriber::Upsert
  extend ActiveSupport::Concern

  def fetch
    begin
      super
    rescue self.class.missing_record_exception
      Promiscuous.warn "[receive] upserting #{payload}"
      klass.new.tap { |o| o.id = id }
    end
  end
end
