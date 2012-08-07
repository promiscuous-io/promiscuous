module ModelsHelper
  def load_models
    define_constant('PublisherModel') do
      include Mongoid::Document

      field :field_1
      field :field_2
      field :field_3
    end


    define_constant('PublisherModelChild', PublisherModel) do
      field :child_field_1
      field :child_field_2
      field :child_field_3
    end


    define_constant('PublisherModelEmbedded') do
      include Mongoid::Document
      embedded_in :publisher_model_embeds

      field :embedded_field_1
      field :embedded_field_2
      field :embedded_field_3
    end

    define_constant('PublisherModelEmbeddedChild', PublisherModelEmbedded) do
      embedded_in :publisher_model_embeds

      field :child_embedded_field_1
      field :child_embedded_field_2
      field :child_embedded_field_3
    end

    define_constant('PublisherModelEmbed') do
      include Mongoid::Document

      embeds_one :model_embedded, :class_name => 'PublisherModelEmbedded'

      field :field_1
      field :field_2
      field :field_3
    end

    define_constant('PublisherModelEmbedChild', PublisherModelEmbed) do
      field :child_field_1
      field :child_field_2
      field :child_field_3
    end

    ##############################################

    define_constant('SubscriberModel') do
      include Mongoid::Document

      field :field_1
      field :field_2
      field :field_3
    end

    define_constant('SubscriberModelChild', SubscriberModel) do
      field :child_field_1
      field :child_field_2
      field :child_field_3
    end

    define_constant('SubscriberModelEmbedded') do
      include Mongoid::Document
      embedded_in :subscriber_model_embeds

      field :embedded_field_1
      field :embedded_field_2
      field :embedded_field_3
    end

    define_constant('SubscriberModelEmbeddedChild', SubscriberModelEmbedded) do
      embedded_in :subscriber_model_embeds
      field :child_embedded_field_1
      field :child_embedded_field_2
      field :child_embedded_field_3
    end

    define_constant('SubscriberModelEmbed') do
      include Mongoid::Document

      embeds_one :model_embedded, :class_name => 'SubscriberModelEmbedded'

      field :field_1
      field :field_2
      field :field_3
    end

    define_constant('SubscriberModelEmbedChild', SubscriberModelEmbed) do
      field :child_field_1
      field :child_field_2
      field :child_field_3
    end
  end
end
