class Promiscuous::Publisher::Operation::NonPersistent < Promiscuous::Publisher::Operation::Base
  def initialize(options={})
    super
  end

  def execute_instrumented(db_operation)
    db_operation.call_and_remember_result(:instrumented)

    unless db_operation.failed?
      trace_operation
    end
  end
end
