class Promiscuous::Observer
  extend ActiveModel::Callbacks
  attr_accessor :id
  define_model_callbacks :create, :update, :destroy, :only => :after
end
