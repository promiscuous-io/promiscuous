module Promiscuous::Publisher::Polymorphic
  extend ActiveSupport::Concern
  include Promiscuous::Publisher::Envelope

  def payload
    super.merge(:type => instance.class.to_s)
  end
end
