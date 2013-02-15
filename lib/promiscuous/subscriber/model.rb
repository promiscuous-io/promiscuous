module Promiscuous::Subscriber::Model
  extend Promiscuous::Autoload
  autoload :Base, :ActiveRecord, :Mongoid, :Observer

  mattr_accessor :mapping
  self.mapping = {}
end
