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
  end

  def self.class_name
    if self.klass
      self.klass
    elsif name
      guess_class_name('Publishers')
    end
  end

  def initialize
    self.id = BSON::ObjectId.new
    self.new_record = true
  end

  def save
    Promiscuous::Subscriber.process(payload)
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
