require 'fnv'
require 'robust-redis-lock'

class Promiscuous::Subscriber::UnitOfWork
  attr_accessor :message

  def initialize(message)
    self.message = message
  end

  def app
    message.parsed_payload['app']
  end

  def operations
    message.parsed_payload['operations'].map { |op| Promiscuous::Subscriber::Operation.new(op) }
  end

  def self.process(*args)
    raise "Same thread is processing a message?" if self.current

    begin
      self.current = new(*args)
      self.current.process_message
    ensure
      self.current = nil
    end
  end

  def self.current
    Thread.current[:promiscuous_message_processor]
  end

  def self.current=(value)
    Thread.current[:promiscuous_message_processor] = value
  end

  def process_message

    Promiscuous.debug "****************************************"
    Promiscuous.debug "****************************************"
    Promiscuous.debug "Promiscuous::Subscriber::UnitOfWork - process_message"
    Promiscuous.debug "****************************************"
    Promiscuous.debug "****************************************"

    #binding.pry

    begin
      on_message
    rescue Exception => e
      Promiscuous::Config.error_notifier.call(e)
      message.nack
      raise e if Promiscuous::Config.test_mode
    end
  end

  LOCK_OPTIONS = { :timeout => 1.5.minute, # after 1.5 minute, we give up
                   :sleep   => 0.1,        # polling every 100ms.
                   :expire  => 1.minute }  # after one minute, we are considered dead

  def with_instance_locked_for(operation, &block)
    return yield unless operation.version

    key = "#{app}:#{operation.key}"
    lock = Redis::Lock.new(key, LOCK_OPTIONS.merge(:redis => Promiscuous::Redis.connection))

    unless lock.lock
      raise Promiscuous::Error::LockUnavailable.new(lock.key)
    end

    begin
      yield
    ensure
      unless lock.unlock
        # TODO Be safe in case we have a duplicate message and lost the lock on it
        raise "The subscriber lost the lock during its operation. It means that someone else\n"+
          "received a duplicate message, and we got screwed.\n"
      end
    end
  end

  # XXX Used for hooking into e.g. by promiscuous-newrelic
  def execute_operation(operation)

    Promiscuous.debug "****************************************"
    Promiscuous.debug "****************************************"
    Promiscuous.debug "Promiscuous::Subscriber::UnitOfWork - execute_operation"
    Promiscuous.debug "Promiscuous::Subscriber::UnitOfWork - operation: #{operation}"
    #Promiscuous.debug "Promiscuous::Subscriber::UnitOfWork - routing: #{self.routing.to_s}"
    Promiscuous.debug "****************************************"
    Promiscuous.debug "****************************************"

    with_instance_locked_for(operation) do
      operation.execute
    end
  end

  def on_message

    Promiscuous.debug "****************************************"
    Promiscuous.debug "****************************************"
    Promiscuous.debug "Promiscuous::Subscriber::UnitOfWork - on_message"
    Promiscuous.debug "Promiscuous::Subscriber::UnitOfWork - operations1: #{self}"
    #Promiscuous.debug "Promiscuous::Subscriber::UnitOfWork - operations2: #{self.operations}"
    Promiscuous.debug "****************************************"
    Promiscuous.debug "****************************************"

    #binding.pry

    with_transaction do
      self.operations.each { |op| execute_operation(op) if op.model }
    end
    message.ack
  end

  private

  def with_transaction(&block)
    if defined?(ActiveRecord::Base)
      ActiveRecord::Base.transaction { yield }
    else
      yield
    end
  end
end
