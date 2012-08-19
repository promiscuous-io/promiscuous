module Promiscuous::Publisher
  autoload :ActiveRecord, 'promiscuous/publisher/active_record'
  autoload :Mongoid,      'promiscuous/publisher/mongoid'
  autoload :Mock,         'promiscuous/publisher/mock'
  autoload :Lint,         'promiscuous/publisher/lint'

  def self.lint(*args)
    Lint.lint(*args)
  end
end
