module Promiscuous::Convenience
  def without_promiscuous(options={}, &block)
    with_promiscuous(:without => true, &block)
  end

  def with_promiscuous(options={}, &block)
    raise "No block given" unless block
    old_disabled, Promiscuous::Publisher::Transaction.disabled = Promiscuous::Publisher::Transaction.disabled, !!options[:without]
    block.call
  ensure
    Promiscuous::Publisher::Transaction.disabled = old_disabled
  end
end

class ::Array
  def without_promiscuous
    raise "what is this block?" if block_given?
    self
  end
end
