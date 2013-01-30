class Promiscuous::Error::Connection < RuntimeError
  attr_accessor :which

  def initialize(which, msg)
    self.which = which
    super(msg)
  end
end
