module Promiscuous::DSL
  def define(&block)
    instance_eval(&block)
  end

  def publish(models, options, &block)
    publisher_definition = PublisherDefinition.new(models, options)
    publisher_definition.instance_eval(&block)
  end

  def subscribe(models, options, &block)
    subscriber_definition = SubscriberDefinition.new(models, options)
    subscriber_definition.instance_eval(&block)
  end

  class PublisherDefinition
    def initialize(models, options)
      @models = models
      @options = options
    end

    def attributes(*fields)
      model_class = @models.to_s.singularize.classify.constantize
      model_class.publish *fields, @options
    end
  end

  class SubscriberDefinition
    def initialize(models, options)
      @models = models
      @options = options
    end

    def attributes(*fields)
      model_class = @models.to_s.singularize.classify.constantize
      model_class.subscribe *fields, @options
    end
  end
end
