class Promiscuous::Railtie < Rails::Railtie
  module TransactionMiddleware
    def process_action(*args)
      Promiscuous.transaction("#{self.class.name}/#{self.action_name}") do
        super
      end
    end
  end

  initializer 'load promiscuous' do
    config.after_initialize do
      Promiscuous::Config.configure unless Promiscuous::Config.configured?
      Promiscuous::Loader.prepare
      ActionController::Base.__send__(:include, TransactionMiddleware)

      ActionDispatch::Reloader.to_prepare do
        Promiscuous::Loader.prepare
      end
      ActionDispatch::Reloader.to_cleanup do
        Promiscuous::Loader.cleanup
      end
    end
  end
end
