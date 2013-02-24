module Promiscuous::DSL
  def define(&block)
    instance_eval(&block)
  end

  def publish(model, options={}, &block)
    Definition.new(:publish, model, options).instance_eval(&block)
  end

  def subscribe(model, options={}, &block)
    Definition.new(:subscribe, model, options).instance_eval(&block)
  end

  class Definition
    def initialize(mode, model, options)
      @mode = mode
      @model = model
      @options = options
      @model_class = @model.to_s.singularize.classify.constantize

      promiscuous_include = mode == :publish ? Promiscuous::Publisher : Promiscuous::Subscriber
      @model_class.class_eval { include promiscuous_include }
    end

    def attributes(*fields)
      @model_class.__send__(@mode, *fields, @options)
    end

    def track_dependencies_of(field)
      @model_class.track_dependencies_of(field)
    end

    alias attribute attributes
  end
end
