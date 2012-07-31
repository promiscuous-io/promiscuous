require 'active_support/core_ext'
require 'bunny'

module Replicable
  module AMQP
    mattr_accessor :connection

    def self.configure
      self.connection = Bunny.new
      self.connection.start
    end

    def self.publish(msg)
      connection.exchange('main', :type => :topic).publish(msg[:payload], :key => msg[:key])
    end
  end
end
