module Promiscuous::Common
  autoload :Options, 'promiscuous/common/options'

  def self.lint(*args)
    Lint.lint(*args)
  end
end
