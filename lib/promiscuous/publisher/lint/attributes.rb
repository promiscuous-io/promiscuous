module Promiscuous::Publisher::Lint::Attributes
  extend ActiveSupport::Concern

  def lint
    super

    instance = klass.new
    publisher.options[:attributes].each do |attr|
      instance.respond_to?(attr) or instance.__send__(attr)
    end
  end

  included { use_option(:klass) }
end
