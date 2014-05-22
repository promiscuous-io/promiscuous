module ModelsHelper
  def load_models_mongoid
    define_constant :PublisherModel do
      include Mongoid::Document
      include Promiscuous::Publisher

      field :field_1
      field :field_2
      field :field_3
      field :unpublished

      publish :field_1, :field_2, :field_3
    end

    define_constant :PublisherModelOther do
      include Mongoid::Document
      include Promiscuous::Publisher

      publish do
        field :field_1
        field :field_2
        field :field_3
      end
    end

    define_constant :PublisherModelChild, PublisherModel do
      field :child_field_1
      field :child_field_2
      field :child_field_3

      publish :child_field_1, :child_field_2, :child_field_3
    end

    define_constant('PublisherModelChildOfChild', PublisherModelChild) do
      field :child_of_child_field_1

      publish :as => :PublisherModelChildOfChild
      publish :child_of_child_field_1
    end

    define_constant :PublisherModelAnotherChild, PublisherModel do
      field :another_child_field_1
      field :another_child_field_2
      field :another_child_field_3

      publish :another_child_field_1, :another_child_field_2, :another_child_field_3
    end

    define_constant :PublisherModelEmbedded do
      include Mongoid::Document
      include Promiscuous::Publisher

      embedded_in :publisher_model_embeds

      field :embedded_field_1
      field :embedded_field_2
      field :embedded_field_3

      publish :embedded_field_1, :embedded_field_2, :embedded_field_3
    end

    define_constant :PublisherModelEmbeddedChild, PublisherModelEmbedded do
      embedded_in :publisher_model_embeds

      field :child_embedded_field_1
      field :child_embedded_field_2
      field :child_embedded_field_3

      publish :child_embedded_field_1, :child_embedded_field_2, :child_embedded_field_3
    end

    define_constant :PublisherModelEmbed do
      include Mongoid::Document
      include Promiscuous::Publisher

      embeds_one :model_embedded, :class_name => 'PublisherModelEmbedded'

      field :field_1
      field :field_2
      field :field_3

      publish :to => 'publisher_model_embed'
      publish :field_1, :field_2, :field_3, :model_embedded
    end

    define_constant :PublisherModelEmbedMany do
      include Mongoid::Document
      include Promiscuous::Publisher
      embeds_many :models_embedded, :class_name => 'PublisherModelEmbedded'

      field :field_1
      field :field_2
      field :field_3

      publish :field_1, :field_2, :field_3, :models_embedded
    end

    define_constant :'Scoped::ScopedPublisherModel', PublisherModel do
    end

    define_constant :PublisherModelBelongsTo do
      include Mongoid::Document
      include Promiscuous::Publisher

      publish do
        belongs_to :publisher_model
      end
    end

    define_constant :PublisherDslModel do
      include Mongoid::Document

      field :field_1
      field :field_2
    end

    define_constant :PublisherModelWithoutSubscriber do
      include Mongoid::Document
      include Promiscuous::Publisher

      publish do
        field :field_1
      end
    end

    ##############################################

    define_constant :SubscriberModel do
      include Mongoid::Document
      include Promiscuous::Subscriber

      field :field_1
      field :field_2
      field :field_3

      field :publisher_id, :type => BSON::ObjectId

      subscribe :field_1, :field_2, :field_3, :as => :PublisherModel
    end

    define_constant :SubscriberModelOther do
      include Mongoid::Document
      include Promiscuous::Subscriber

      subscribe :as => :PublisherModelOther do
        field :field_1
        field :field_2
        field :field_3
      end
    end

    define_constant :SubscriberModelChild, SubscriberModel do
      field :child_field_1
      field :child_field_2
      field :child_field_3

      subscribe :as => :PublisherModelChild
      subscribe :child_field_1, :child_field_2, :child_field_3
    end

    define_constant :SubscriberModelAnotherChild, SubscriberModel do
      field :another_child_field_1
      field :another_child_field_2
      field :another_child_field_3

      subscribe :as => :PublisherModelAnotherChild
      subscribe :another_child_field_1, :another_child_field_2, :another_child_field_3
    end

    define_constant :SubscriberModelEmbedded do
      include Mongoid::Document
      include Promiscuous::Subscriber
      embedded_in :subscriber_model_embeds

      field :embedded_field_1
      field :embedded_field_2
      field :embedded_field_3

      subscribe :as => :PublisherModelEmbedded
      subscribe :embedded_field_1, :embedded_field_2, :embedded_field_3
    end

    define_constant :SubscriberModelEmbeddedChild, SubscriberModelEmbedded do
      embedded_in :subscriber_model_embeds
      field :child_embedded_field_1
      field :child_embedded_field_2
      field :child_embedded_field_3

      subscribe :as => :PublisherModelEmbeddedChild
      subscribe :embedded_field_1, :embedded_field_2, :embedded_field_3
    end

    define_constant :SubscriberModelEmbed do
      include Mongoid::Document
      include Promiscuous::Subscriber
      embeds_one :model_embedded, :class_name => 'SubscriberModelEmbedded',
                 :cascade_callbacks => true

      field :field_1
      field :field_2
      field :field_3

      subscribe :as => :PublisherModelEmbed
      subscribe :field_1, :field_2, :field_3, :model_embedded
    end

    define_constant :SubscriberModelEmbedMany do
      include Mongoid::Document
      include Promiscuous::Subscriber
      embeds_many :models_embedded, :class_name => 'SubscriberModelEmbedded',
                  :cascade_callbacks => true

      field :field_1
      field :field_2
      field :field_3

      subscribe :as => :PublisherModelEmbedMany
      subscribe :field_1, :field_2, :field_3, :models_embedded
    end

    define_constant :'Scoped::ScopedSubscriberModel', SubscriberModel do
    end

    define_constant :SubscriberModelBelongsTo do
      include Mongoid::Document
      include Promiscuous::Subscriber

      subscribe :as => :PublisherModelBelongsTo do
        field :publisher_model_id, :type => BSON::ObjectId
      end
    end

    define_constant :SubscriberDslModel do
      include Mongoid::Document

      field :field_1
      field :field_2
      field :publisher_id, :type => BSON::ObjectId
    end
  end
end
