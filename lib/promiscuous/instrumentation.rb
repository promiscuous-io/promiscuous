module Promiscuous::Instrumentation
  singleton_class.send(:attr_accessor, :files)
  self.files = {}

  def instrument(type, options={}, &block)
    instr_file_name = Promiscuous::Config.intrumentation_file
    return block.call unless instr_file_name

    start_time = Time.now.to_f
    r = block.call
    end_time = Time.now.to_f

    desc = options[:desc]
    desc = instance_eval(&desc) if desc.is_a?(Proc)

    if !options[:if] || options[:if].call
      file = (Promiscuous::Instrumentation.files[instr_file_name] ||= File.open(instr_file_name, 'a'))
      file.puts "[#{Promiscuous::Config.app}] #{type} #{start_time}-#{end_time} #{desc}"
      file.flush
    end

    r
  end
end
