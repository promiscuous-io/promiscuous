module Test
  module Publisher
    class Parent
      include Mongoid::Document
      include Replicable::Publisher

      field :parent_field_1
      field :parent_field_2
      field :parent_field_3

      replicate :parent_field_1, :parent_field_2
    end

    class Child < Parent
      include Mongoid::Document
      include Replicable::Publisher

      field :child_field_1
      field :child_field_2
      field :child_field_3

      replicate :child_field_1, :child_field_2
    end
  end

  module Subscriber
    class Child
      include Mongoid::Document
      include Replicable::Subscriber

      field :parent_field_1
      field :child_field_1
      field :child_field_2
      field :child_field_3

      replicate :parent_field_1, :child_field_1, :child_field_2, :child_field_3
    end
  end
end
