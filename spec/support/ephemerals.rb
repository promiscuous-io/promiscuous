module EphemeralsHelper
  def load_ephemerals
    define_constant(:ModelEphemeral, Promiscuous::Ephemeral) do
      attr_accessor :field_1
      attr_accessor :field_2
      attr_accessor :field_3
    end
  end
end
