class Promiscuous::Subscriber::Worker < Celluloid::SupervisionGroup
  extend Promiscuous::Autoload
  autoload :Message, :Pump, :MessageSynchronizer, :Runner, :Stats, :Recorder

  pool      Runner,              :as => :runners, :size => ENV['THREADS'].try(:to_i) || 10
  supervise MessageSynchronizer, :as => :message_synchronizer
  supervise Pump,                :as => :pump
  supervise Stats,               :as => :stats
end
