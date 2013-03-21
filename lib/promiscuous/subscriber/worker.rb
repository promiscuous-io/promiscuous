class Promiscuous::Subscriber::Worker < Celluloid::SupervisionGroup
  extend Promiscuous::Autoload
  autoload :Message, :Pump, :MessageSynchronizer, :Runner, :Stats, :Recorder

  pool      Runner,              :as => :runners, :size => 10
  supervise MessageSynchronizer, :as => :message_synchronizer
  supervise Pump,                :as => :pump
  supervise Stats,               :as => :stats

  def finalize
    # The order matters as actors depend on each other.
    # This is fixed in the new celluloid, but the gem is not published yet.
    [:pump, :message_synchronizer, :stats, :runners].each do |actor_name|
      Celluloid::Actor[actor_name].terminate
    end
  end
end
