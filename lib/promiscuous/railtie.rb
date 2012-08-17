module Promiscuous
  class Railtie < Rails::Railtie
    rake_tasks { load 'promiscuous/railtie/replicate.rake' }

    initializer 'load promiscuous' do
      config.after_initialize do
        Promiscuous::Loader.load_descriptors(:publishers)
        ActionDispatch::Reloader.to_prepare do
          Promiscuous::Loader.load_descriptors
        end
      end
    end
  end
end
