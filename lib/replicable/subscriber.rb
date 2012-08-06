class Replicable::Subscriber
  mattr_accessor :subscriptions
  self.subscriptions = Set.new

  class_attribute :binding, :model, :fields
  attr_accessor :instance, :operation, :type

  def self.subscribe(options={})
    self.model = options[:model]
    self.binding = options[:from]
    self.fields = options[:fields]

    if self.fields
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

    Replicable::Subscriber.subscriptions << self
  end
end
