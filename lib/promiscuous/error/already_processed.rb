class Promiscuous::Error::AlreadyProcessed < Promiscuous::Error::Base
  def to_s
    "Skipping message (already processed)"
  end
end
