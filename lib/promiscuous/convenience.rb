module Promiscuous::Convenience
  def without_promiscuous
    Thread.current[:promiscuous_disabled] = true
    yield
  ensure
    Thread.current[:promiscuous_disabled] = false
  end
end
