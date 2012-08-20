module Promiscuous::Publisher
  autoload :ActiveRecord, 'promiscuous/publisher/active_record'
  autoload :AMQP,         'promiscuous/publisher/amqp'
  autoload :Attributes,   'promiscuous/publisher/attributes'
  autoload :Base,         'promiscuous/publisher/base'
  autoload :Class,        'promiscuous/publisher/class'
  autoload :Envelope,     'promiscuous/publisher/envelope'
  autoload :Lint,         'promiscuous/publisher/lint'
  autoload :Mock,         'promiscuous/publisher/mock'
  autoload :Model,        'promiscuous/publisher/model'
  autoload :Mongoid,      'promiscuous/publisher/mongoid'
  autoload :Polymorphic,  'promiscuous/publisher/polymorphic'

  def self.lint(*args)
    Lint.lint(*args)
  end
end
