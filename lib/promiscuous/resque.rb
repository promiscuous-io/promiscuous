require 'resque/job'

class Resque::Job
  alias_method :perform_without_promiscuous, :perform

  def perform
    name = "resque/#{payload_class.name.underscore}"
    Promiscuous::Middleware.with_context(name) do
      perform_without_promiscuous
    end
  end
end
