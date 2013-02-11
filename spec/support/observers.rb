module ObserversHelper
  def load_observers
    define_constant :ModelObserver do
      include Promiscuous::Subscriber::Model::Observer
      attr_accessor :field_1, :field_2, :field_3
      subscribe :field_1, :field_2, :field_3, :from => 'crowdtap/publisher_model'
    end
  end
end
