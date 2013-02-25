module Promiscuous::Convenience
  def without_promiscuous
    raise "No block given" unless block_given?
    old_disabled, Promiscuous::Publisher::Transaction.disabled = Promiscuous::Publisher::Transaction.disabled, true
    yield
  ensure
    Promiscuous::Publisher::Transaction.disabled = old_disabled
  end

  # alias for Promiscuous.transaction
  def with_promiscuous(*args, &block)
    Promiscuous::Publisher::Transaction.open(*args, &block)
  end
end

module Enumerable
  def without_read_dependencies
    self
  end
end
