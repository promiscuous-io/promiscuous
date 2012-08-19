module Promiscuous
  module Loader
    def self.load_descriptors(descriptors=[:publishers, :subscribers])
      [descriptors].flatten.each do |descriptor|
        dir, file_matcher = case descriptor
          when :publishers then %w(publishers **_publisher.rb)
          when :subscribers then %w(subscribers **_subscriber.rb)
          end

        Dir[Rails.root.join('app', dir, file_matcher)].map do |file|
          File.basename(file, ".rb").camelize.constantize
        end
      end
    end

    def self.unload_descriptors(descriptors=[:publishers, :subscribers])
      [descriptors].flatten.each do |descriptor|
        dir, file_matcher = case descriptor
          when :publishers then # TODO Cleanup publishers
          when :subscribers then Promiscuous::Subscriber::AMQP.subscribers.clear
          end
      end
    end
  end
end
