module Test
  module Primary
    class Parent
      include Mongoid::Document
      include Replicable::Primary

      field :parent_field_1
      field :parent_field_2
      field :parent_field_3

      replicate :parent_field_1, :parent_field_2
    end

    class Child < Parent
      include Mongoid::Document
      include Replicable::Primary

      field :child_field_1
      field :child_field_2
      field :child_field_3

      replicate :child_field_1, :child_field_2
    end
  end
end
