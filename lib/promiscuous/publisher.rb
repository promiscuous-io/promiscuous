module Promiscuous::Publisher
  extend Promiscuous::Autoload
  autoload :ActiveRecord, :AMQP, :Attributes, :Base, :Class, :Envelope, :Lint,
           :Mock, :Model, :Mongoid, :Polymorphic, :Error, :Ephemeral

  def self.lint(*args)
    Lint.lint(*args)
  end
end
