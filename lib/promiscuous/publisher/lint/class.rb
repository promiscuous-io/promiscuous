module Promiscuous::Publisher::Lint::Class
  extend ActiveSupport::Concern

  def lint
    super

    if publisher.klass != klass
      msg = "Please define a publisher for #{klass}"
      msg = "#{msg} because #{parent} is published and you need to cover subclasses" if parent
      raise msg
    end
  end

  included { use_option :klass, :parent }
end
