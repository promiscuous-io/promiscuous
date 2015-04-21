class Promiscuous::Backend::Null
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
end
