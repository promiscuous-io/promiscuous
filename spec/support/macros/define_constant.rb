require 'set'

module DefineConstantMacros
  def define_constant(class_name, base = Object, &block)
    name = class_name.to_s.split("::")
    if name.length > 1
      module_name = name.first
      klass_name = name.last

      if Object.const_defined?(module_name)
        mod = Object.const_get(module_name)
      else
        mod = Module.new
        Object.const_set(module_name, mod)
      end

      klass = Class.new(base)
      mod.const_set(klass_name, klass)

      klass.class_eval(&block) if block_given?

      @defined_constants[mod] ||= []
      @defined_constants[mod] << klass_name
    else
      klass = Class.new(base)
      Object.const_set(class_name, klass)

      klass.class_eval(&block) if block_given?

      @defined_constants[Object] ||= []
      @defined_constants[Object] << class_name
    end

    klass
  end
end

RSpec.configure do |config|
  config.before do
    @defined_constants = {}
  end

  config.after do
    @defined_constants.to_a.each do |base, class_names|
      class_names.each do |class_name|
        base.send(:remove_const, class_name)
      end
    end
  end

  config.include DefineConstantMacros
end
