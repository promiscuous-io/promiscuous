module StubHook
  class Control < Struct.new(:active, :instance, :arguments, :skip_next_call)
    def initialize
      self.active = true
      self.instance = nil
      self.arguments = nil
      self.skip_next_call = false
    end

    def unstub!
      self.active = false
    end

    def skip_next_call!
      self.skip_next_call = true
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

        if control.skip_next_call
          control.skip_next_call = false
        else
          __send__("#{method}_stubbed", *args, &block)
        end
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
