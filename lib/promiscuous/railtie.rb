class Promiscuous::Railtie < Rails::Railtie
  initializer 'load promiscuous' do
    ActiveSupport.on_load(:action_controller) do
      include Promiscuous::Middleware::Controller
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

  # XXX Only Rails 3.x support
  console do
    class << IRB
      alias_method :start_without_promiscuous, :start

      def start(*args, &block)
        return start_without_promiscuous(*args, &block) if Promiscuous::Publisher::Context.current
        Promiscuous::Middleware.with_context 'rails/console' do
          start_without_promiscuous(*args, &block)
        end
      end
    end

    if defined?(Pry)
      class << Pry
        alias_method :start_without_promiscuous, :start

        def start(*args, &block)
          return start_without_promiscuous(*args, &block) if Promiscuous::Publisher::Context.current
          Promiscuous::Middleware.with_context 'rails/console' do
            start_without_promiscuous(*args, &block)
          end
        end
      end
    end
  end
end
