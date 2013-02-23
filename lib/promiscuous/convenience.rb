module Promiscuous::Convenience
  def without_promiscuous
    old_value, Thread.current[:promiscuous_disabled] = Thread.current[:promiscuous_disabled], true
    yield
  ensure
    Thread.current[:promiscuous_disabled] = old_value
  end
end
