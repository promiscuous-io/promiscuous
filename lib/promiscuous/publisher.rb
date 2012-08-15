module Promiscuous::Publisher
  autoload :ActiveRecord, 'promiscuous/publisher/active_record'
  autoload :Mongoid,      'promiscuous/publisher/mongoid'
  autoload :Mock,         'promiscuous/publisher/mock'
end
