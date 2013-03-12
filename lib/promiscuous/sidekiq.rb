module Sidekiq
  class Promiscuous
    def call(worker_class, item, queue)
      ::Promiscuous::Middleware.with_context "sidekiq/#{item['queue']}/#{worker_class.class.to_s.underscore}" do
        yield
      end
    end
  end
end

Sidekiq.configure_server do |config|
  config.server_middleware do |chain|
    chain.add Sidekiq::Promiscuous
  end
end
