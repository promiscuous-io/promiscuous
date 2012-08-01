module Replicable
  class Railtie < Rails::Railtie
    rake_tasks { load 'replicable/railtie/replicate.rake' }
  end
end
