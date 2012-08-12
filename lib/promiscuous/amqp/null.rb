module Promiscuous
  module AMQP
    module Null
      def self.connect
      end

      def self.disconnect
      end

      def self.publish(msg)
      end

      def self.subscribe(options={}, &block)
      end
    end
  end
end
