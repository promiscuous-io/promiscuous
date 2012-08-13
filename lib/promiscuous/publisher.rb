module Promiscuous::Publisher
  require 'promiscuous/publisher/active_record' if defined?(ActiveRecord)
  require 'promiscuous/publisher/mongoid' if defined?(Mongoid)
end
