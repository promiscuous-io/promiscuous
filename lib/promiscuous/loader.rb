module Promiscuous
  module Loader
    def self.load_descriptors(descriptors=[:publishers, :subscribers])
      [descriptors].flatten.each do |descriptor|
        dir, file_matcher = case descriptor
          when :publishers
            require 'promiscuous/publisher'
            # TODO Cleanup publishers
            %w(publishers **_publisher.rb)
          when :subscribers
            require 'promiscuous/subscriber'
            Promiscuous::Subscriber.subscribers.clear
            %w(subscribers **_subscriber.rb)
          end

        Dir[Rails.root.join('app', dir, file_matcher)].map do |file|
          File.basename(file, ".rb").camelize.constantize
        end
      end
    end
  end
end
