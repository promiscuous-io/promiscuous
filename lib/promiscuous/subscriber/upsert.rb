module Promiscuous::Subscriber::Upsert
  extend ActiveSupport::Concern

  def fetch
    begin
      super
    rescue self.class.missing_record_exception
      Promiscuous.warn "[receive] upserting #{payload}"
      fetch_new
    end
  end
end
