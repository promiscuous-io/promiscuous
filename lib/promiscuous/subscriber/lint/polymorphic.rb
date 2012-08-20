module Promiscuous::Subscriber::Lint::Polymorphic
  extend ActiveSupport::Concern

  def publisher
    parent_publisher = super
    return nil if parent_publisher.nil?

    publishers.
      select { |pub| pub <= parent_publisher }.
      select { |pub| pub.class_name == subscriber.from_type }.
      first
  end

  def lint
    super
    return if skip_polymorphic

    sub_descendants = subscriber.descendants
    pub_descendants = publishers.select { |pub| pub < publisher }

    if check_publisher
      subscriber_types = sub_descendants.map &:from_type
      publisher_types = pub_descendants.map &:class_name
      missing_types = publisher_types - subscriber_types
      if missing_types.present?
        raise "#{subscriber} does not cover #{missing_types.join(", ")}"
      end
    end

    sub_descendants.each do |pub|
      self.class.new(options.merge(:klass => nil, :subscriber => pub,
                                   :skip_polymorphic => true)).lint
    end
  end

  included do
    use_option :skip_polymorphic
  end
end
