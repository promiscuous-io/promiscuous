class Promiscuous::Railtie < Rails::Railtie
  initializer 'load promiscuous' do
    config.before_initialize do
      ActionController::Base.__send__(:include, Promiscuous::Middleware::Controller)
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

  console do
    class << IRB
      alias_method :start_without_promiscuous, :start

      def start
        Promiscuous.context do
          start_without_promiscuous
        end
      end
    end
  end
end
