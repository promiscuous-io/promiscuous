module ModelsHelper
  def load_models_active_record
    define_constant :PublisherModel, ActiveRecord::Base do
      include Promiscuous::Publisher
      publish :field_1, :field_2, :field_3
    end

    define_constant :PublisherModelOther, ActiveRecord::Base do
      include Promiscuous::Publisher
      publish :field_1, :field_2, :field_3
    end

    define_constant :PublisherModelChild, PublisherModel do
      publish :child_field_1, :child_field_2, :child_field_3
    end

    define_constant('Scoped::ScopedPublisherModel', PublisherModel) do
    end

    define_constant :PublisherDslModel, ActiveRecord::Base do
    end

    define_constant :PublisherModelBelongsTo, ActiveRecord::Base do
      include Promiscuous::Publisher

      publish do
        belongs_to :publisher_model
      end
    end

    ##############################################

    define_constant :SubscriberModel, ActiveRecord::Base do
      include Promiscuous::Subscriber
      subscribe :field_1, :field_2, :field_3, :as => :PublisherModel
    end

    define_constant :SubscriberModelOther, ActiveRecord::Base do
      include Promiscuous::Subscriber
      subscribe :field_1, :field_2, :field_3, :as => :PublisherModelOther
    end

    define_constant :SubscriberModelChild, SubscriberModel do
      subscribe :as => :SubscriberModelChild
      subscribe :child_field_1, :child_field_2, :child_field_3
    end

    define_constant :'Scoped::ScopedSubscriberModel', SubscriberModel do
    end

    define_constant :SubscriberDslModel, ActiveRecord::Base do
    end

    define_constant :SubscriberModelBelongsTo, ActiveRecord::Base do
      include Promiscuous::Subscriber

      subscribe :as => :PublisherModelBelongsTo
      subscribe :publisher_model_id
    end
  end
end
