require 'promiscuous/publisher/model'

module Promiscuous::Subscriber::Mongoid::Root
  extend ActiveSupport::Concern
  include Promiscuous::Subscriber::Model
end
