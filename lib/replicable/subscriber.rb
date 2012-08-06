class Replicable::Subscriber
  mattr_accessor :subscriptions
  self.subscriptions = Set.new

  class_attribute :binding, :model, :models, :fields
  attr_accessor :instance, :operation, :type

  def self.subscribe(options={})
    self.model   = options[:model]
    self.models  = options[:models]
    self.binding = options[:from]
    self.fields  = options[:fields]

    generate_replicate_from_fields if fields
    Replicable::Subscriber.subscriptions << self
  end

  def self.generate_replicate_from_fields
    define_method "replicate" do |payload|
      self.class.fields.each do |field|
        optional = field.to_s[-1] == '?'
        field = field.to_s[0...-1].to_sym if optional
        setter = :"#{field}="

        if !optional or instance.respond_to?(setter)
          instance.__send__(setter, payload[field]) if payload[field]
        end
      end
    end
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
end
