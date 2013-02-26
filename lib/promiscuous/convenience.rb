module Promiscuous::Convenience
  Transaction = Promiscuous::Publisher::Transaction
  extend self

  def without_promiscuous
    raise "No block given" unless block_given?
    old_disabled, Transaction.disabled = Transaction.disabled, true
    yield
  ensure
    Transaction.disabled = old_disabled
  end
end

class ::Array
  def without_promiscuous
    raise "What is this block?" if block_given?
    self
  end
end
