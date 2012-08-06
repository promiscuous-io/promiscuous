class Replicable::Subscriber
  mattr_accessor :subscriptions, :binding_map
  self.subscriptions = Set.new

  class_attribute :amqp_binding, :model, :models, :attributes
  attr_accessor :id, :instance, :operation, :type, :parent, :getter, :payload

  def self.subscribe(options={})
    self.model        = options[:model]
    self.models       = options[:models]
    self.amqp_binding = options[:from]
    self.attributes   = options[:attributes]

    Replicable::Subscriber.subscriptions << self
  end

  def model
    if self.class.models
      self.class.models[type]
    elsif self.class.model
      self.class.model
    else
      raise "Cannot find matching model.\n" +
            "I don't want to be rude or anything, but have you defined your target model?"
    end
  end

  def initialize(options={})
    @id        = options[:id]
    @type      = options[:type]
    @operation = options[:operation].to_sym
    @payload   = options[:payload].symbolize_keys
    @parent    = options[:parent]
    @getter    = options[:getter]
  end

  def fetch_instance
    @instance = if parent
                  case operation
                  when :create
                    model.new.tap {|m| m.id = id}
                  when :update
                    parent.send(getter)
                  when :destroy
                    nil
                  end
                else
                  case operation
                  when :create
                    model.new.tap {|m| m.id = id}
                  when :update
                    model.find(id)
                  when :destroy
                    model.find(id)
                  end
                end
  end

  def replicate
    self.class.attributes.each do |field|
      optional = field.to_s[-1] == '?'
      field = field.to_s[0...-1].to_sym if optional
      setter = :"#{field}="
      value = payload[field]

      set_attribute(setter, field, optional, value)
    end
  end

  def set_attribute(setter, field, optional, value)
    if value and !optional || instance.respond_to?(setter)
      if value.is_a?(Hash) and value['__amqp_binding__']
        value = self.class.process(value, :parent => instance, :getter => field).instance
      end
      instance.__send__(setter, value)
    end
  end

  def commit_instance
    case operation
    when :create
      instance.save
    when :update
      instance.save
    when :destroy
      instance.destroy
    end
  end

  def self.process(amqp_payload, options={})
    amqp_payload.symbolize_keys!
    binding = amqp_payload[:__amqp_binding__]
    subscriber_class = binding_map[binding]
    raise "FATAL: Unknown binding: '#{binding}'" if subscriber_class.nil?

    subscriber = subscriber_class.new(amqp_payload.merge(options))
    subscriber.fetch_instance
    subscriber.replicate
    subscriber.commit_instance unless subscriber.parent
    subscriber
  end

  def self.prepare_bindings
    self.binding_map = {}
    Replicable::Subscriber.subscriptions.each do |subscriber|
      self.binding_map[subscriber.amqp_binding] = subscriber
    end
  end

end
