class Promiscuous::Publisher::Operation::Ephemeral < Promiscuous::Publisher::Operation::Base
  def initialize(options={})
    super
    @instance = options[:instance]
  end

  def instances
    [@instance].compact
  end

  def execute_instrumented(query)
    create_transport_batch([self]).publish(true)
  end

  def increment_version_in_document
    # No op
  end
end
