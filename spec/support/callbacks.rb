module CallbacksHelper
  def record_callbacks(klass)
    klass.class_eval do
      class_attribute :callbacks
      self.callbacks = {}

      after_create  { (self.class.callbacks[id] ||= []) << :create  }
      after_update  { (self.class.callbacks[id] ||= []) << :update  }
      after_save    { (self.class.callbacks[id] ||= []) << :save    }
      after_destroy { (self.class.callbacks[id] ||= []) << :destroy }
    end
  end
end
