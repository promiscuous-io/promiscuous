module Promiscuous::ControllerMiddleware
  extend ActiveSupport::Concern

  def process_action(*args)
    Promiscuous::Publisher::Context::Base.current.current_user = self.current_user if self.respond_to?(:current_user)
    super
    Promiscuous::Publisher::Context::Base.current.current_user = nil
  end
end

class Promiscuous::Railtie < Rails::Railtie
  initializer 'load promiscuous' do
    ActiveSupport.on_load(:action_controller) do
      include Promiscuous::ControllerMiddleware
    end

    config.after_initialize do
      Promiscuous::Config.configure unless Promiscuous::Config.configured?
      Promiscuous::Loader.prepare

      ActionDispatch::Reloader.to_prepare do
        Promiscuous::Loader.prepare
      end
      ActionDispatch::Reloader.to_cleanup do
        Promiscuous::Loader.cleanup
      end
    end
  end
end
