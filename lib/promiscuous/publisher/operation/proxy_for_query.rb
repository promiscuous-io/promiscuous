class Promiscuous::Publisher::Operation::ProxyForQuery
  attr_accessor :exception, :result, :operation

  def initialize(operation, &block)
    @operation = operation
    @queries = {}

    if block
      if block.arity == 1
        block.call(self)
      else
        self.non_instrumented { block.call }
        self.instrumented { block.call }
      end
    end
  end

  def prepare(&block)
    @queries[:prepare] = block
  end

  def non_instrumented(&block)
    @queries[:non_instrumented] = block
  end

  def instrumented(&block)
    @queries[:instrumented] = block
  end

  def call_and_remember_result(which)
    raise "Fatal: #{which} query unspecified" unless @queries[which]
    @result = @queries[which].call(@operation)
  rescue Exception => e
    @exception = e
  end

  def failed?
    !!@exception
  end

  def result
    failed? ? (raise @exception) : @result
  end
end
