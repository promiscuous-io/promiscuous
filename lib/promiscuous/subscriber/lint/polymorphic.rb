module Promiscuous::Subscriber::Lint::Polymorphic
  extend ActiveSupport::Concern

  def publisher
    parent_publisher = super
    if parent_publisher
      if parent_publisher.class_name == subscriber.from_type
        parent_publisher
      else
        parent_publisher.descendants.
          select { |pub| pub.class_name == subscriber.from_type }.
          first
      end
    end
  end

  def lint
    super

    if check_publisher
      subscriber_types = subscriber.descendants.map &:from_type
      publisher_types = publisher.descendants.map &:class_name
      missing_types = publisher_types - subscriber_types
      if missing_types.present?
        raise "#{publisher} misses some child types: #{missing_types.join(", ")}"
      end
    end

    unless skip_polymorphic
      subscriber.descendants.each do |pub|
        self.class.new(options.merge(:publisher => pub,
                                     :skip_polymorphic => true)).lint
      end
    end
  end

  included do
    use_option :skip_polymorphic
  end
end
