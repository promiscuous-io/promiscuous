module MocksHelper
  def load_mocks
    define_constant :MockModel do
      include Promiscuous::Publisher::Model::Mock
      publish :field_1, :field_2, :field_3
      mock    :id => :bson if ORM.has(:mongoid)
    end
  end
end
