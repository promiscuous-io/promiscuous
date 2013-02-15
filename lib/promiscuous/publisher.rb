module Promiscuous::Publisher
  extend Promiscuous::Autoload
  autoload :Model, :Operation, :MockGenerator

  extend ActiveSupport::Concern

  included do
    include Model::Mongoid      if defined?(Mongoid::Document)  && self < Mongoid::Document
    include Model::ActiveRecord if defined?(ActiveRecord::Base) && self < ActiveRecord::Base
    raise "What kind of model is this? try including Promiscuous::Publisher after all your includes" unless self < Model::Base
  end
end
