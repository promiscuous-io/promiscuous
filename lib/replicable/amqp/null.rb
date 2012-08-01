module Replicable
  module AMQP
    module Null
      def self.configure(options)
      end

      def self.publish(msg)
      end

      def self.subscribe(options={}, &block)
      end

      def self.clear
      end

      def self.close
      end
    end
  end
end
