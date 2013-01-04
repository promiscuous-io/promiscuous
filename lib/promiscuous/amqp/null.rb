module Promiscuous
  module AMQP
    module Null
      def self.connect
      end

      def self.disconnect
      end

      def self.connected?
      end

      def self.publish(options={})
      end

      def self.open_queue(options={}, &block)
      end
    end
  end
end
