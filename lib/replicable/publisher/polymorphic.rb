require 'replicable/publisher/envelope'

module Replicable::Publisher::Polymorphic
  extend ActiveSupport::Concern
  include Replicable::Publisher::Envelope

  def payload
    super.merge(:type => instance.class.to_s)
  end
end
