module Replicable::Subscriber::Mongoid::Root
  extend ActiveSupport::Concern

  def fetch
    case operation
    when :create
      klass.new.tap { |o| o.id = id }
    when :update
      klass.find(id)
    when :destroy
      klass.find(id)
    end
  end

  def process_attributes?
    operation != :destroy
  end

  def process
    super
    case operation
    when :create
      instance.save!
    when :update
      instance.save!
    when :destroy
      instance.destroy
    end
  end

  included do
    use_payload_attribute :id
    use_payload_attribute :operation, :symbolize => true
  end
end
