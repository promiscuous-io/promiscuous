module Promiscuous::Autoload
  include ActiveSupport::Autoload

  def autoload(*args)
    args.each { |mod| super mod }
  end
end
