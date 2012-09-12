module Promiscuous::Common::ClassHelpers
  extend ActiveSupport::Concern

  module ClassMethods
    def guess_class_name(separator)
      return nil if name.nil?
      class_name = name.split("::").reverse.take_while { |name| name != separator }.reverse.join('::')
      class_name = $1 if class_name =~ /^(.+)#{separator.singularize}$/
      class_name
    end
  end
end
