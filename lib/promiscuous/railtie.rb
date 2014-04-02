class Promiscuous::Railtie < Rails::Railtie
  initializer 'load promiscuous' do
    config.before_initialize do
      Promiscuous.configure do |config|
        config.max_retries = 0 unless Rails.env.production?
      end
    end

    config.after_initialize do
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
