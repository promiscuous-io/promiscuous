module Promiscuous::Publisher::Lint::AMQP
  extend ActiveSupport::Concern

  def lint
    super

    pub_to = publisher_instance.to
    if pub_to != to
      raise "#{publisher} publishes #{klass} to #{pub_to} instead of #{to}"
    end
  end

  included { use_option(:to) }
end
