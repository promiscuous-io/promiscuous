class Promiscuous::Error::NestedTransaction < RuntimeError
  def to_s
    "Promiscuous doesn't support nested transactions, because we don't know what it would mean."
  end
end
