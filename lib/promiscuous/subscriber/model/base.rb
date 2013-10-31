module Promiscuous::Subscriber::Model::Base
  extend ActiveSupport::Concern

  def __promiscuous_update(payload, options={})
    self.class.subscribed_attrs.map(&:to_s).each do |attr|
      unless payload.attributes.has_key?(attr)
        "Attribute '#{attr}' is missing from the payload".tap do |error_msg|
          Promiscuous.warn "[receive] #{error_msg}"
          raise error_msg unless Promiscuous::Config.relaxed_schema
        end
      end

      value = payload.attributes[attr]
      update = true

      attr_payload = Promiscuous::Subscriber::Operation.new(value)
      if model = attr_payload.model
        # Nested subscriber
        old_value =  __send__(attr)
        instance = old_value || model.__promiscuous_fetch_new(attr_payload.id)

        if instance.class != model
          # Because of the nasty trick with 'promiscuous_embedded_many'
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

      self.subscribe_foreign_key = options[:foreign_key] if options[:foreign_key]

      ([self] + descendants).each { |klass| klass.subscribed_attrs |= attributes }

      if self.subscribe_from && options[:from] && self.subscribe_from != options[:from]
        raise 'Subscribing from different publishers is not supported yet'
      end

      self.subscribe_from ||= options[:from].try(:to_s) || "*"

      self.register_klass(options)
    end

    def register_klass(options={})
      subscribe_as = options[:as].try(:to_s) || self.name
      return unless subscribe_as

      Promiscuous::Subscriber::Model.mapping[self.subscribe_from] ||= {}
      Promiscuous::Subscriber::Model.mapping[self.subscribe_from][subscribe_as] = self
    end

    def inherited(subclass)
      super
      subclass.subscribed_attrs = self.subscribed_attrs.dup
      subclass.register_klass
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
