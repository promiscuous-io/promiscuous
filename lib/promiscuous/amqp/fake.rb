module Promiscuous
  module AMQP
    module Fake
      mattr_accessor :messages, :subscribe_options
      self.messages = []

      def self.configure(options)
      end

      def self.publish(msg)
        self.messages << msg
      end

      def self.subscribe(options={}, &block)
        self.subscribe_options = options
      end

      def self.clear
        self.messages.clear
        self.subscribe_options = nil
      end

      def self.close
      end
    end
  end
end
