module Promiscuous::Publisher::Lint::Polymorphic
  extend ActiveSupport::Concern

  def lint
    super

    unless skip_polymorphic
      klass.descendants.each do |subclass|
        pub = Promiscuous::Publisher::Lint.get_publisher(subclass)
        self.class.new(options.merge(:klass => subclass,
                                     :publisher => pub,
                                     :skip_polymorphic => true)).lint
      end
    end
  end

  included do
    use_option(:klass)
    use_option(:skip_polymorphic)
  end
end
