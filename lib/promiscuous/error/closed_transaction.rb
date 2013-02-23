class Promiscuous::Error::ClosedTransaction < Promiscuous::Error::Base
  def to_s
    "Promiscuous was told to close the transaction a while ago. You cannot write anymore."
  end
end
