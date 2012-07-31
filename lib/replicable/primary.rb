require 'active_support/concern'
require 'replicable/helpers'
require 'replicable/amqp'

module Replicable::Primary
  extend ActiveSupport::Concern

  module ClassMethods
    def replicate(*fields)
      unless defined?(replicate_fields)
        class_attribute :replicate_fields
        [:create, :update, :destroy].each do |operation|
          __send__("around_#{operation}", "replicate_changes_#{operation}".to_sym)
        end
      end

      self.replicate_fields ||= []

      # Appending (<<) would not work in the case of a subclass
      # because the subclass needs to use the class attribute setter
      # to get its own copy.
      self.replicate_fields += fields
    end
  end

  private

  def replicated_field_names
    self.class.replicate_fields.select do |field|
      self.__send__("#{field}_changed?")
    end
  end

  def replicate_key(operation)
    path = ['crowdtap']
    path << Replicable::Helpers.model_ancestors(self.class).map {|c| c.to_s.underscore}.join(',')
    path << operation
    path << replicated_field_names.join(',')
    path.join('.')
  end

  def replicate_payload
    Hash[(replicated_field_names + [:id]).map {|f| [f, self.__send__(f)] }]
  end

  [:create, :update, :destroy].each do |operation|
    define_method "replicate_changes_#{operation}" do |&block|
      key = replicate_key(operation)
      payload = replicate_payload
      block.call
      Replicable::AMQP.publish(:key => key, :payload => payload)
    end
  end
end
