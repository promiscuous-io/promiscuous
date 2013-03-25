class Promiscuous::Subscriber::Worker < Celluloid::SupervisionGroup
  extend Promiscuous::Autoload
  autoload :Message, :Pump, :MessageSynchronizer, :Runner, :Stats, :Recorder
  task_class TaskThread

  NUM_THREADS = ENV['THREADS'].try(:to_i) || 10

  if NUM_THREADS > 1
    pool      Runner, :as => :runners, :size => NUM_THREADS
  else
    supervise Runner, :as => :runners
  end

  supervise MessageSynchronizer, :as => :message_synchronizer
  supervise Pump,                :as => :pump
  supervise Stats,               :as => :stats
end
