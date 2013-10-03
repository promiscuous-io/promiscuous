class Promiscuous::Publisher::Context::Transaction
  attr_accessor :driver

  def initialize(driver)
    @driver = driver

    @indexes = []
    @write_operations = []
  end

  def start
    @indexes << @write_operations.size
  end

  def add_write_operation(operation)
    @write_operations << operation
  end

  def write_operations_to_commit
    transaction_index = @indexes.last
    @write_operations[transaction_index..-1]
  end

  def rollback
    transaction_index = @indexes.pop
    @write_operations.slice!(transaction_index..-1)
  end

  def commit
    @indexes.pop
  end

  def in_transaction?
    !@indexes.empty?
  end
end
