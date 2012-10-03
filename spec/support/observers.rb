module ObserversHelper
  def load_observers
    define_constant(:ModelObserver, Promiscuous::Observer) do
      include ActiveSupport::Callbacks

      attr_accessor :id
      attr_accessor :field_1
      attr_accessor :field_2
      attr_accessor :field_3
    end
  end
end
