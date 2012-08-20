module Promiscuous::Subscriber::Lint::AMQP
  extend ActiveSupport::Concern

  def publisher
    Promiscuous::Publisher::Mock.descendants.
      select { |pub| pub.superclass == Promiscuous::Publisher::Mock }.
      select { |pub| pub.to == from }.
      tap { |pubs| raise "#{from} has multiple publishers: #{pubs}" if pubs.size > 1 }.
      first
  end

  def lint
    super

    if check_publisher
      raise "No publisher found for #{publisher}" if publisher.nil?
    end
  end

  included { use_option :from }
end
