module Promiscuous::Subscriber::Lint::Class
  extend ActiveSupport::Concern

  def lint
    super

    if klass && subscriber.klass != klass
      raise "Subscriber #{subscriber} does not replicate #{klass}"
    end
  end

  included { use_option :klass }
end
