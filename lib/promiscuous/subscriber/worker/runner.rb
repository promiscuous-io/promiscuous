class Promiscuous::Subscriber::Worker::Runner
  include Celluloid
  task_class TaskThread

  def process(msg)
    msg.process
  end
end
