module Promiscuous::Subscriber::Lint::Attributes
  extend ActiveSupport::Concern

  def lint
    super

    instance = subscriber.klass.new
    subscriber.attributes.each do |attr|
      instance.respond_to?("#{attr}=") or instance.__send__("#{attr}=")
    end

    if check_publisher
      missing_attributes = subscriber.attributes - publisher.attributes
      if missing_attributes.present?
        raise "#{publisher} subscribes to non published attributes: #{missing_attributes.join(", ")}"
      end
    end
  end
end
