module CallbacksHelper
  extend self

  def record_callbacks(klass)
    klass.class_eval do
      after_create  { CallbacksHelper.record_callback(self, :create)  }
      after_update  { CallbacksHelper.record_callback(self, :update)  }
      after_save    { CallbacksHelper.record_callback(self, :save)    }
      after_destroy { CallbacksHelper.record_callback(self, :destroy) }

      def callbacks(options={})
        CallbacksHelper.get_callbacks(options.merge(:klass => self.class, :id => id))
      end

      def self.num_saves
        callbacks(:only => :save).count
      end

      def self.callbacks(options={})
        CallbacksHelper.get_callbacks(options.merge(:klass => self))
      end
    end
  end

  def clear_callbacks
    $callbacks = []
  end

  def record_callback(instance, which)
    $callbacks << {:klass => instance.class, :id => instance.id, :which => which}
  end

  def get_callbacks(options={})
    callbacks = $callbacks
    callbacks = callbacks.select { |cb| cb[:klass] == options[:klass] } if options[:klass]
    callbacks = callbacks.select { |cb| cb[:id]    == options[:id]    } if options[:id]
    callbacks = callbacks.select { |cb| cb[:which] == options[:only]  } if options[:only]
    callbacks.map { |cb| cb[:which] }
  end
end

RSpec.configure do |config|
  config.before do
    CallbacksHelper.clear_callbacks
  end
end
