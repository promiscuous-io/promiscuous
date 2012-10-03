class Promiscuous::Observer
  extend ActiveModel::Callbacks
  define_model_callbacks :create, :update, :destroy, :only => :after
end
