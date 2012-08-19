module Promiscuous::Publisher::Lint::Attributes
  extend ActiveSupport::Concern

  def lint
    super

    instance = klass.new
    publisher.attributes.each do |attr|
      instance.respond_to?(attr) or instance.__send__(attr)
    end
  end
end
