require 'active_support/concern'
require 'replicable/helpers'
require 'replicable/amqp'

module Replicable::Publisher
  extend ActiveSupport::Concern

  module ClassMethods
    def replicate(options={})
      unless defined?(replicate_options)
        class_attribute :replicate_options
        [:create, :update, :destroy].each do |operation|
          __send__("around_#{operation}", "replicate_changes_#{operation}".to_sym)
        end
      end

      # The subclass needs to use the class attribute setter to get its own
      # copy.
      self.replicate_options = Marshal.load(Marshal.dump(self.replicate_options))

      self.replicate_options ||= {}
      self.replicate_options[:fields] ||= []
      #self.replicate_options[:fields] += options[:fields]
      self.replicate_options[:app_name] = options[:app_name] if options[:app_name]
    end
  end

  private

  def replicated_field_names
    (self.class.fields.keys - ["_id", "_type"]).select do |field|
      self.__send__("#{field}_changed?")
    end
  end

  def replicate_key(operation)
    path = [self.class.replicate_options[:app_name] || Replicable::AMQP.app]
    path << Replicable::Helpers.model_ancestors(self.class).map {|c| c.to_s.underscore}.join('.')
    path << operation
    path << '$fields$'
    path << replicated_field_names.join('.')
    path.join('.')
  end

  def replicate_payload(operation)
    {
      :id => id,
      :operation => operation,
      :fields => Hash[(replicated_field_names).map {|f| [f, self.__send__(f)] }]
    }.to_json
  end

  [:create, :update, :destroy].each do |operation|
    define_method "replicate_changes_#{operation}" do |&block|
      key = replicate_key(operation)
      payload = replicate_payload(operation)
      block.call
      Replicable::AMQP.publish(:key => key, :payload => payload)
    end
  end
end
