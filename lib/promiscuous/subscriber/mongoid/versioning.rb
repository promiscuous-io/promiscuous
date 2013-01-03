module Promiscuous::Subscriber::Mongoid::Versioning
  extend ActiveSupport::Concern

  module AtomicSelector
    extend ActiveSupport::Concern

    def atomic_selector
      if use_atomic_promiscuous_selector
        super.merge({ '$or' => [{'_psv' => { '$lte'    => self._psv }},
                                {'_psv' => { '$exists' => false     }}]})
      else
        super
      end
    end

    included do
      attr_accessor :use_atomic_promiscuous_selector
      field :_psv, :type => Integer
    end
  end

  def save_instance
    if version
      instance._psv = version
      instance.use_atomic_promiscuous_selector = true
    end
    super
  ensure
    instance.use_atomic_promiscuous_selector = false
  end

  included { use_payload_attribute :version }

  module ClassMethods
    def setup_class_binding
      super
      klass.__send__(:include, AtomicSelector) if klass
    end
  end
end
