module Promiscuous::Subscriber
  extend Promiscuous::Autoload
  autoload :Worker, :MessageProcessor, :Model, :Operation

  extend ActiveSupport::Concern

  included do
    if defined?(Mongoid::Document) && self < Mongoid::Document
      include Promiscuous::Subscriber::Model::Mongoid
    elsif defined?(ActiveRecord::Base) && self < ActiveRecord::Base
      include Promiscuous::Subscriber::Model::ActiveRecord
    else
      raise "What kind of model is this? try including Promiscuous::Subscriber after all your includes"
    end
  end
end
