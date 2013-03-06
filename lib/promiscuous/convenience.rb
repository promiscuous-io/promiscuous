module Promiscuous::Convenience
  extend self

  def without_promiscuous
    raise "No block given" unless block_given?
    old_disabled, Promiscuous.disabled = Promiscuous.disabled, true
    yield
  ensure
    Promiscuous.disabled = old_disabled
  end
end

class ::Array
  def without_promiscuous
    raise "What is this block?" if block_given?
    self
  end
end
