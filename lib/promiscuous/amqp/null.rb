class Promiscuous::AMQP::Null
  def connect
  end

  def disconnect
  end

  def connected?
    true
  end

  def publish(options={})
    options[:on_confirm].try(:call)
  end

  def open_queue(options={}, &block)
  end
end
