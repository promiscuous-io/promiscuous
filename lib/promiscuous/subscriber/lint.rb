module Promiscuous::Subscriber::Lint
  autoload :Base,        'promiscuous/subscriber/lint/base'
  autoload :Class,       'promiscuous/subscriber/lint/class'
  autoload :Attributes,  'promiscuous/subscriber/lint/attributes'
  autoload :Polymorphic, 'promiscuous/subscriber/lint/polymorphic'
  autoload :AMQP,        'promiscuous/subscriber/lint/amqp'

  def self.lint(binding_classes)
    Base.reload_publishers

    binding_classes.each do |from, klass|
      sub = Promiscuous::Subscriber::AMQP.subscribers[from]
      raise "#{from} has no subscriber" if sub.nil?

      lint = ::Class.new(Base)
      lint.__send__(:include, Class)       if sub.include?(Promiscuous::Subscriber::Class)
      lint.__send__(:include, Attributes)  if sub.include?(Promiscuous::Subscriber::Attributes)
      lint.__send__(:include, AMQP)        if sub.include?(Promiscuous::Subscriber::AMQP)
      lint.__send__(:include, Polymorphic) if sub.include?(Promiscuous::Subscriber::Polymorphic)
      lint.new(:klass => klass, :subscriber => sub, :from => from).lint
    end
    true
  end
end
