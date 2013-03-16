module Promiscuous::Subscriber::Model::Base
  extend ActiveSupport::Concern

  def __promiscuous_update(payload, options={})
    self.class.subscribed_attrs.map(&:to_s).each do |attr|
      unless payload.attributes.has_key?(attr)
        raise "Attribute '#{attr}' is missing from the payload"
      end

      value = payload.attributes[attr]
      update = true

      attr_payload = Promiscuous::Subscriber::Payload.new(value)
      if model = attr_payload.model
        # Nested subscriber
        old_value =  __send__(attr)
        instance = old_value || model.__promiscuous_fetch_new(attr_payload.id)

        if instance.class != model
          # Because of the nasty trick with '__promiscuous__/embedded_many'
          instance = model.__promiscuous_fetch_new(attr_payload.id)
        end

        nested_options = {:parent => self, :old_value => old_value}
        update = instance.__promiscuous_update(attr_payload, nested_options)
        value = instance
      end

      self.__send__("#{attr}=", value) if update
      true
    end
  end

  included do
    class_attribute :promiscuous_root_class
    class_attribute :subscribe_from, :subscribe_foreign_key, :subscribed_attrs
    self.promiscuous_root_class = self
    self.subscribe_foreign_key = :id
    self.subscribed_attrs = []
  end

  module ClassMethods
    def subscribe(*args)
      options    = args.extract_options!
      attributes = args

      # TODO reject invalid options

      if attributes.present? && self.subscribe_from && options[:from] && self.subscribe_from != options[:from]
        raise 'Subscribing from different publishers is not supported yet'
      end

      unless self.subscribe_from
        self.subscribe_from = options[:from] || ".*/#{self.name.underscore}"
        from_regexp = Regexp.new("^#{self.subscribe_from}$")
        Promiscuous::Subscriber::Model.mapping[from_regexp] = self
      end

      self.subscribe_foreign_key = options[:foreign_key] if options[:foreign_key]
      @subscribe_as = options[:as].to_s if options[:as]

      ([self] + descendants).each { |klass| klass.subscribed_attrs |= attributes }
    end

    def subscribe_as
      @subscribe_as || name
    end

    def inherited(subclass)
      super
      subclass.subscribed_attrs = self.subscribed_attrs.dup
    end

    class None; end
    def __promiscuous_missing_record_exception
      None
    end

    def __promiscuous_fetch_new(id)
      new.tap { |m| m.__send__("#{subscribe_foreign_key}=", id) }
    end

    def __promiscuous_fetch_existing(id)
      key = subscribe_foreign_key
      if promiscuous_root_class.respond_to?("find_by_#{key}!")
        promiscuous_root_class.__send__("find_by_#{key}!", id)
      elsif respond_to?("find_by")
        promiscuous_root_class.find_by(key => id)
      else
        instance = promiscuous_root_class.where(key => id).first
        raise __promiscuous_missing_record_exception.new(promiscuous_root_class, id) if instance.nil?
        instance
      end
    end
  end
end
