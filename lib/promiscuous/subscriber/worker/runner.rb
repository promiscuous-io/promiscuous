class Promiscuous::Subscriber::Worker::Runner
  include Celluloid

  def process(msg, current_version)
    msg.process(current_version)
  end
end
