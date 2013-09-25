class Promiscuous::Publisher::Bootstrap::Connection
  def initialize
    # We don't put the connection in the initializer because it gets funny when
    # it comes to the disconnection.
    connection_options = { :url      => Promiscuous::Config.publisher_amqp_url,
                           :exchange => Promiscuous::AMQP::BOOTSTRAP_EXCHANGE }
    connection, channel, @exchange = Promiscuous::AMQP.new_connection(connection_options)
    # TODO on_confirm
  ensure
    if connection
      # TODO not very pretty... We should abstract that
      channel.respond_to?(:stop)    ? channel.stop    : channel.close
      connection.respond_to?(:stop) ? connection.stop : connection.close
      @exchange = nil
    end
  end

  def publish(options={})
    options[:key]      ||= "#{Promiscuous::Config.app}/__bootstrap__"
    options[:exchange] ||= @exchange
    Promiscuous::AMQP.publish(options)
  end
end
