require 'active_support/concern'
require 'replicable/helpers'
require 'replicable/amqp'

module Replicable::Publisher
  extend ActiveSupport::Concern
  include Replicable::Helpers

  module ClassMethods
    def replicate(options={})
      unless replicated_called?
        class_attribute :replicate_options
        [:create, :update, :destroy].each do |operation|
          __send__("around_#{operation}", "replicate_changes_#{operation}".to_sym)
        end
      end
      super
    end

  end

  private

  def replicated_field_names
    self.class.replicate_options[:fields].select do |field|
      self.__send__("#{field}_changed?")
    end
  end

  def with_replicated_field_names_cached
    @replicated_field_names = replicated_field_names
    yield
    @replicated_field_names = nil
  end

  def replicate_key(operation)
    path = [self.class.replicate_options[:app_name] || Replicable::AMQP.app]
    path << self.class.replicate_ancestors.join('.')
    path << operation
    path.join('.')
  end

  def replicate_payload(operation)
    {
      :id        => id,
      :operation => operation,
      :classes   => self.class.replicate_ancestors,
      :fields    => Hash[(@replicated_field_names).map {|f| [f, self.__send__(f)] }]
    }.to_json
  end

  [:create, :update, :destroy].each do |operation|
    define_method "replicate_changes_#{operation}" do |&block|
      with_replicated_field_names_cached do
        block.call
        if replicated_field_names.present? || operation != :update
          Replicable::AMQP.publish(:key => replicate_key(operation),
                                   :payload => replicate_payload(operation))
        end
      end
    end
  end
end
