class Promiscuous::Publisher::Model::Mock
  extend ActiveSupport::Concern
  include Promiscuous::Publisher::Model::Ephemeral

  def promiscuous_sync(options={}, &block)
    Promiscuous::Subscriber.process(JSON.parse(to_promiscuous(options).to_json))
  end
end
