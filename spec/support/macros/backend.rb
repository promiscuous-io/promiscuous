module BackendMacro
  extend self

  def backend_up!
    if Promiscuous::Backend.driver.respond_to?(:orig_raw_publish)
      Promiscuous::Backend.driver.class_eval { alias_method :raw_publish, :orig_raw_publish }
    end
  end

  def backend_down!
    prepare

    Promiscuous::Backend.driver.class_eval { def raw_publish(*args); raise RuntimeError.new("backend DOWN!!!"); end }
  end

  def backend_delayed!
    prepare

    Promiscuous::Backend.driver.class_eval do
      cattr_accessor :delayed
      self.delayed = []

      def raw_publish(*args)
        self.delayed << args
      end
    end
  end

  def backend_process_delayed!
    Promiscuous::Backend.driver.delayed.each { |args| Promiscuous::Backend.driver.raw_publish(*args) }
    Promiscuous::Backend.driver.delayed = []
  end

  private

  def prepare
    Promiscuous::Backend.driver.class_eval { alias_method :orig_raw_publish, :raw_publish }
  end
end

RSpec.configure do |config|
  config.after do
    BackendMacro.backend_up!
  end

  config.include BackendMacro
end
