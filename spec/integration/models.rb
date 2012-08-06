class PublisherModel
  include Mongoid::Document

  field :field_1
  field :field_2
  field :field_3
end

class PublisherModelChild < PublisherModel
  field :child_field_1
  field :child_field_2
  field :child_field_3
end

class PublisherModelEmbedded
  include Mongoid::Document
  embedded_in :publisher_model_embeds

  field :embedded_field_1
  field :embedded_field_2
  field :embedded_field_3
end

class PublisherModelEmbeddedChild < PublisherModelEmbedded
  embedded_in :publisher_model_embeds

  field :child_embedded_field_1
  field :child_embedded_field_2
  field :child_embedded_field_3
end

class PublisherModelEmbed
  include Mongoid::Document

  embeds_one :model_embedded, :class_name => 'PublisherModelEmbedded'

  field :field_1
  field :field_2
  field :field_3
end

class PublisherModelEmbedChild < PublisherModelEmbed
  field :child_field_1
  field :child_field_2
  field :child_field_3
end

##############################################

class SubscriberModel
  include Mongoid::Document

  field :field_1
  field :field_2
  field :field_3
end

class SubscriberModelChild < SubscriberModel
  field :child_field_1
  field :child_field_2
  field :child_field_3
end

class SubscriberModelEmbedded
  include Mongoid::Document
  embedded_in :subscriber_model_embeds

  field :embedded_field_1
  field :embedded_field_2
  field :embedded_field_3
end

class SubscriberModelEmbeddedChild < SubscriberModelEmbedded
  embedded_in :subscriber_model_embeds
  field :child_embedded_field_1
  field :child_embedded_field_2
  field :child_embedded_field_3
end

class SubscriberModelEmbed
  include Mongoid::Document

  embeds_one :model_embedded, :class_name => 'SubscriberModelEmbedded'

  field :field_1
  field :field_2
  field :field_3
end

class SubscriberModelEmbedChild < SubscriberModelEmbed
  field :child_field_1
  field :child_field_2
  field :child_field_3
end
