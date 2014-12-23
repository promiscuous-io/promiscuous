class Promiscuous::Publisher::Operation::Ephemeral < Promiscuous::Publisher::Operation::Base
  def initialize(options={})
    super
    @routing = options[:routing]
    @exchange = options[:exchange]
    self.instances = [options[:instance]]
  end

  def execute_instrumented(query)
    generate_instances_payload_and_queue
    publish_payloads_async(:exchange => @exchange, :routing => @routing, :raise_error => true)
  end

  def increment_version_in_document
    # No op
  end
end
