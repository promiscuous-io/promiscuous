module Promiscuous::Subscriber::Lint::Attributes
  extend ActiveSupport::Concern

  def lint
    super

    instance = subscriber.klass.new
    attributes = subscriber.attributes
    attributes += [subscriber.foreign_key] if subscriber.foreign_key

    attributes.each { |attr| instance.respond_to?("#{attr}=") or instance.__send__("#{attr}=") }

    if check_publisher
      raise "The publisher of #{subscriber} does not exist" if publisher.nil?
      missing_attributes = subscriber.attributes - publisher.attributes
      if missing_attributes.present?
        raise "#{publisher} subscribes to non published attributes: #{missing_attributes.join(", ")}"
      end
    end
  end
end
