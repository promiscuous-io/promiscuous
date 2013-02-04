require 'eventmachine'

class Promiscuous::Subscriber::Worker::Pump
  include Celluloid

  def initialize
    # signals do not work when initializing with Celluloid
    # I wish ruby had semaphores, it would make much more sense.
    @initialize_mutex = Mutex.new
    @initialization_done = ConditionVariable.new

    @em_thread = Thread.new { EM.run { start } }

    # The event machine thread will unlock us
    wait_for_initialization
    raise @exception if @exception
  end

  def wait_for_initialization
    @initialize_mutex.synchronize do
      @initialization_done.wait(@initialize_mutex)
    end
  end

  def finalize_initialization
    @initialize_mutex.synchronize do
      @initialization_done.signal
    end
  end

  def finalize
    @dont_reconnect = true
    EM.next_tick do
      Promiscuous::AMQP.disconnect
      EM.stop
    end
    @em_thread.join
  rescue
    # Let amqp die like a pro
  end

  def force_use_ruby_amqp
    Promiscuous::AMQP.disconnect
    Promiscuous::Config.backend = :rubyamqp
    Promiscuous::AMQP.connect
  end

  def start
    force_use_ruby_amqp
    Promiscuous::AMQP.open_queue(queue_bindings) do |queue|
      queue.subscribe :ack => true do |metadata, payload|
        process_payload(metadata, payload)
      end
    end
  rescue Exception => @exception
  ensure
    finalize_initialization
  end

  def process_payload(metadata, payload)
    msg = Promiscuous::Subscriber::Worker::Message.new(metadata, payload)
    Celluloid::Actor[:message_synchronizer].process_when_ready(msg)
  end

  def queue_bindings
    queue_name = "#{Promiscuous::Config.app}.promiscuous"
    exchange_name = Promiscuous::AMQP::EXCHANGE

    # We need to subscribe to everything to keep up with the version tracking
    bindings = ['*']
    {:exchange_name => exchange_name, :queue_name => queue_name, :bindings => bindings}
  end
end
