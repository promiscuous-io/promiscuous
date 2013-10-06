module StubHook
  class Control < Struct.new(:active, :instance, :arguments)
    def initialize
      self.active = true
      self.instance = nil
      self.arguments = nil
    end

    def unstub!
      self.active = false
    end
  end

  def stub_before_hook(klass, method, &before_call)
    @stub_hooks << [klass, method]

    mutex = Mutex.new
    control = Control.new

    klass.class_eval do
      alias_method "#{method}_stubbed", method

      define_method(method) do |*args, &block|
        if control.active
          mutex.synchronize do
            control.instance = self
            control.arguments = args
            before_call.call(control)
          end
        end

        __send__("#{method}_stubbed", *args, &block)
      end
    end
  end
end

RSpec.configure do |config|
  config.before do
    @stub_hooks = []
  end

  config.after do
    @stub_hooks.each do |klass, method|
      klass.class_eval do
        alias_method method, "#{method}_stubbed"
        #undef "#{method}_stubbed"
      end
    end
  end

  config.include StubHook
end
