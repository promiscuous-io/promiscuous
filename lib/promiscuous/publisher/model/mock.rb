class Promiscuous::Publisher::Model::Mock
  extend ActiveSupport::Concern
  include Promiscuous::Publisher::Model::Ephemeral

  def promiscuous_sync(options={}, &block)
    parsed_payload = JSON.parse(to_promiscuous(options).to_json)
    payload = Promiscuous::Subscriber::Payload.new(parsed_payload)
    Promiscuous::Subscriber::Operation.new(payload).commit
  end
end
