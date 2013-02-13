module Promiscuous::DSL
  def define(&block)
    instance_eval(&block)
  end

  def publish(models, options, &block)
    publisher_definition = Definition.new(:publish, models, options)
    publisher_definition.instance_eval(&block)
  end

  def subscribe(models, options, &block)
    subscriber_definition = Definition.new(:subscribe, models, options)
    subscriber_definition.instance_eval(&block)
  end

  class Definition
    def initialize(mode, models, options)
      @mode = mode
      @models = models
      @options = options
    end

    def attributes(*fields)
      model_class = @models.to_s.singularize.classify.constantize
      model_class.__send__(@mode, *fields, @options)
    end
  end
end
