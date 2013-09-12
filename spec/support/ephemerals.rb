module EphemeralsHelper
  def load_ephemerals
    define_constant :ModelEphemeral  do
      include Promiscuous::Publisher::Model::Ephemeral

      attr_accessor :field_1
      attr_accessor :field_2
      attr_accessor :field_3

      publish :field_1, :field_2, :field_3, :as => :PublisherModel
    end
  end
end
