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
