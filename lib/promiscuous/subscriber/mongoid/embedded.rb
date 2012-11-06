module Promiscuous::Subscriber::Mongoid::Embedded
  extend ActiveSupport::Concern

  def fetch
    (old_value || klass.new).tap { |m| m.id = id }
  end

  def process
    super
    instance.save! if old_value
  end

  def old_value
    options[:old_value]
  end

  included { use_payload_attribute :id }
end
