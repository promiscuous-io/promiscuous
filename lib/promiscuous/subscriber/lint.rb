module Promiscuous::Subscriber::Lint
  extend Promiscuous::Autoload
  autoload :Base, :Class, :Attributes, :Polymorphic, :AMQP

  def self.lint(binding_classes={})
    Base.reload_publishers

    if binding_classes.empty?
      binding_classes = Promiscuous::Subscriber::AMQP.subscribers.reduce({}) do |res, e|
        from, sub = e
        res[from] = sub.klass unless from =~ /^__promiscuous__/
        res
      end
      raise "No subscribers found" if binding_classes.empty?
    end

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
