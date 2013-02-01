class Promiscuous::Subscriber::Worker::Runner
  include Celluloid

  def process(msg)
    msg.process
  end
end
