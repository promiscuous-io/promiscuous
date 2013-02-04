require 'celluloid'
require 'celluloid/io'

class Promiscuous::Subscriber::Worker < Celluloid::SupervisionGroup
  extend Promiscuous::Autoload
  autoload :Message, :Pump, :MessageSynchronizer, :Runner

  pool      Runner,              :as => :runners, :size => 10
  supervise MessageSynchronizer, :as => :message_synchronizer
  supervise Pump,                :as => :pump
end

Celluloid.exception_handler { |e| Promiscuous::Config.error_notifier.try(:call, e) }
