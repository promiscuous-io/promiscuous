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

class ModelEmbedded
  include Mongoid::Document

  embedded_in :publisher_model_embeds

  field :embedded_field_1
  field :embedded_field_2
  field :embedded_field_3
end

class PublisherModelEmbeds
  include Mongoid::Document

  embeds_one :model_embedded

  field :field_1
  field :field_2
  field :field_3
end

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

class SubscriberModelEmbeds
  include Mongoid::Document

  embeds_one :model_embedded

  field :field_1
  field :field_2
  field :field_3
end
