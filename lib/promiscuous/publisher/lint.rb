module Promiscuous::Publisher::Lint
  autoload :Base,        'promiscuous/publisher/lint/base'
  autoload :ClassBind,   'promiscuous/publisher/lint/class_bind'
  autoload :Attributes,  'promiscuous/publisher/lint/attributes'
  autoload :Polymorphic, 'promiscuous/publisher/lint/polymorphic'
  autoload :AMQP,        'promiscuous/publisher/lint/amqp'

  def self.get_publisher(klass)
    unless klass.respond_to?(:promiscuous_publisher)
      raise "#{klass} has no publisher"
    end

    klass.promiscuous_publisher
  end

  def self.lint(classes)
    classes.each do |klass, to|
      pub = get_publisher(klass)

      lint = Class.new(Base)
      lint.__send__(:include, ClassBind)   if pub.include?(Promiscuous::Publisher::ClassBind)
      lint.__send__(:include, Attributes)  if pub.include?(Promiscuous::Publisher::Attributes)
      lint.__send__(:include, Polymorphic) if pub.include?(Promiscuous::Publisher::Polymorphic)
      lint.__send__(:include, AMQP)        if pub.include?(Promiscuous::Publisher::AMQP)
      lint.new(:klass => klass, :publisher => pub, :to => to).lint
    end
    true
  end
end
