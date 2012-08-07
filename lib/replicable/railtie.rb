module Replicable
  class Railtie < Rails::Railtie
    rake_tasks { load 'replicable/railtie/replicate.rake' }

    initializer 'load replicable' do
      # TODO clean that up
      config.after_initialize do
        Dir[Rails.root.join('app', 'publishers', '**_publisher.rb')].map do |file|
          file.split('/')[-1].split('.')[0].camelize.constantize
        end
        ActionDispatch::Reloader.to_prepare do
          Dir[Rails.root.join('app', 'publishers', '**_publisher.rb')].map do |file|
            file.split('/')[-1].split('.')[0].camelize.constantize
          end
        end

        Dir[Rails.root.join('app', 'subscribers', '**_subscriber.rb')].map do |file|
          file.split('/')[-1].split('.')[0].camelize.constantize
        end
        ActionDispatch::Reloader.to_prepare do
          Dir[Rails.root.join('app', 'subscribers', '**_subscriber.rb')].map do |file|
            file.split('/')[-1].split('.')[0].camelize.constantize
          end
        end
      end
    end
  end
end
