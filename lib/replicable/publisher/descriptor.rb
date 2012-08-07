module Replicable::Publisher::Descriptor
  extend ActiveSupport::Concern

  def payload
    { :payload => super }
  end
end
