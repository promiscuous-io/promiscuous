module Promiscuous::Publisher::Lint::ClassBind
  extend ActiveSupport::Concern

  def lint
    super

    if publisher.klass != klass
      raise "Define a publisher for #{klass}"
    end
  end

  included { use_option(:klass) }
end

