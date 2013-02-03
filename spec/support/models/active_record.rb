module ModelsHelper
  def load_models_active_record
    define_constant('PublisherModel', ActiveRecord::Base) do
    end

    define_constant('PublisherModelOther', ActiveRecord::Base) do
    end

    define_constant('PublisherModelChild', PublisherModel) do
    end

    define_constant('Scoped::ScopedPublisherModel', PublisherModel) do
    end

    ##############################################

    define_constant('SubscriberModel', ActiveRecord::Base) do
    end

    define_constant('SubscriberModelOther', ActiveRecord::Base) do
    end

    define_constant('SubscriberModelChild', SubscriberModel) do
    end

    define_constant('Scoped::ScopedSubscriberModel', SubscriberModel) do
    end
  end
end
