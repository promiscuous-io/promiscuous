module Promiscuous::Publisher::Lint
  extend Promiscuous::Autoload
  autoload :Base, :Class, :Attributes, :Polymorphic, :AMQP

  def self.get_publisher(klass)
    unless klass.respond_to?(:promiscuous_publisher)
      raise "#{klass} has no publisher"
    end

    klass.promiscuous_publisher
  end

  def self.lint(class_bindings={})
    if class_bindings.empty?
      class_bindings = Promiscuous::Publisher::Model.klasses.reduce({}) do |res, klass|
        res[klass] = klass.promiscuous_publisher.to
        res
      end

      raise "No publishers found" if class_bindings.empty?
    end

    class_bindings.each do |klass, to|
      pub = get_publisher(klass)

      lint = ::Class.new(Base)
      lint.__send__(:include, Class)       if pub.include?(Promiscuous::Publisher::Class)
      lint.__send__(:include, Attributes)  if pub.include?(Promiscuous::Publisher::Attributes)
      lint.__send__(:include, AMQP)        if pub.include?(Promiscuous::Publisher::AMQP)
      lint.__send__(:include, Polymorphic) if pub.include?(Promiscuous::Publisher::Polymorphic)
      lint.new(:klass => klass, :publisher => pub, :to => to).lint
    end
    true
  end
end
