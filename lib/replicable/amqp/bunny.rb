module Replicable
  module AMQP
    module Bunny
      mattr_accessor :connection

      def self.configure(options)
        require 'bunny'
        self.connection = Bunny.new
        self.connection.start
      end

      def self.publish(msg)
        connection.exchange('replicable', :type => :topic).publish(msg[:payload], :key => msg[:key])
      end

      def self.close
      end
    end
  end
end
