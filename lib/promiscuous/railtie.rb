module Promiscuous
  class Railtie < Rails::Railtie
    initializer 'load promiscuous' do
      config.after_initialize do
        Promiscuous::Loader.load_descriptors(:publishers)
        ActionDispatch::Reloader.to_prepare do
          Promiscuous::Loader.load_descriptors
        end
        ActionDispatch::Reloader.to_cleanup do
          Promiscuous::Loader.unload_descriptors
        end
      end
    end
  end
end
