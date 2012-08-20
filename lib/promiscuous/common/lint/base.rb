module Promiscuous::Common::Lint::Base
  extend ActiveSupport::Concern

  included do
    attr_accessor :options
  end

  def initialize(options)
    self.options = options
  end

  def lint
  end

  module ClassMethods
    def use_option(attr)
      define_method(attr) do
        self.options[attr]
      end
    end
  end
end
