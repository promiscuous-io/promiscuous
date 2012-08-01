module Replicable
  module AMQP
    module Bunny
      mattr_accessor :connection

      def self.configure(options)
        require 'bunny'
        self.connection = ::Bunny.new(options[:server_uri])
        self.connection.start
      end

      def self.publish(msg)
        connection.exchange('replicable', :type => :topic).publish(msg[:payload], :key => msg[:key])
        AMQP.info "[publish] #{msg[:key]} -> #{msg[:payload]}"
      end

      def self.close
        self.connection.stop
      end
    end
  end
end
