module Replicable
  module AMQP
    module Bunny
      mattr_accessor :connection

      def self.configure
        require 'bunny'
        self.connection = Bunny.new
        self.connection.start
      end

      def self.publish(msg)
        connection.exchange('main', :type => :topic).publish(msg[:payload], :key => msg[:key])
      end
    end
  end
end
