module Replicable
  module Helpers
    def self.model_ancestors(model)
      chain = []
      while model.include?(Mongoid::Document) do
        chain << model
        model = model.superclass
      end
      chain.reverse
    end
  end
end
