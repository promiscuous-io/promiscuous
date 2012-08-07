require 'replicable/publisher/descriptor'

module Replicable::Publisher::Polymorphic
  extend ActiveSupport::Concern
  include Replicable::Publisher::Descriptor

  def payload
    super.merge(:type => instance.class.to_s)
  end
end
