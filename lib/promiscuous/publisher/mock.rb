class Promiscuous::Publisher::Mock
  include Promiscuous::Common::ClassHelpers

  def self.publish(options)
    if defined?(attributes)
      if options[:attributes]
        raise "Do not specify the 'to' field in childrens" if options[:to]
        self.attributes = self.attributes + options[:attributes]
      end
    else
      class_attribute :to, :attributes, :klass

      self.to = options[:to]
      self.klass = options[:class]
      self.attributes = options[:attributes].to_a

      attr_accessor :id, :new_record
    end
    attr_accessor *attributes

    associations = attributes.map { |attr| $1 if attr =~ /^(.*)_id$/ }.compact
    associations.each do |attr|
      attr_accessor attr
      define_method("#{attr}=") do |value|
        instance_variable_set("@#{attr}", value)
        instance_variable_set("@#{attr}_id", value.id)
      end
    end
  end

  def self.class_name
    self.klass ? self.klass : guess_class_name('Publishers')
  end

  def initialize
    self.id = BSON::ObjectId.new
    self.new_record = true
  end

  def save
    if payload['__amqp__'].in? Promiscuous::Subscriber::AMQP.subscribers.keys
      Promiscuous::Subscriber.process(payload)
    end
    self.new_record = false
    true
  end
  alias :save! :save

  def update_attributes(attrs)
    attrs.each { |attr, value| __send__("#{attr}=", value) }
    save
  end
  alias :update_attributes! :update_attributes

  def payload
    {
      '__amqp__'  => self.class.to,
      'id'        => self.id,
      'type'      => self.class.class_name,
      'operation' => self.new_record ? 'create' : 'update',
      'payload'   => Hash[self.class.attributes.map { |attr| [attr.to_s, payload_for(attr)] }]
    }
  end

  def payload_for(attr)
    value = __send__(attr)
    value = value.payload if value.is_a?(Promiscuous::Publisher::Mock)
    value
  end

  def destroy
    Promiscuous::Subscriber.process(
      '__amqp__'  => self.class.to,
      'id'        => self.id,
      'type'      => self.class.class_name,
      'operation' => 'destroy'
    )
  end
end
