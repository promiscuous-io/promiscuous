class Promiscuous::Subscriber::Operation::Base
  attr_accessor :model, :id, :operation, :attributes
  delegate :message, :to => :message_processor

  def initialize(payload)
    if payload.is_a?(Hash)
      self.id         = payload['id']
      self.operation  = payload['operation'].try(:to_sym)
      self.attributes = payload['attributes']
      self.model      = self.get_subscribed_model(payload) if payload['types']
    end
  end

  def get_subscribed_model(payload)
    [message.app, '*'].each do |app|
      app_mapping = Promiscuous::Subscriber::Model.mapping[app] || {}
      payload['types'].to_a.each do |ancestor|
        model = app_mapping[ancestor]
        return model if model
      end
    end
    nil
  end

  def warn(msg)
    Promiscuous.warn "[receive] #{msg} #{message.payload}"
  end

  def create(options={})
    model.__promiscuous_fetch_new(id).tap do |instance|
      instance.__promiscuous_update(self, :version => 0)
      instance.save!
    end
  rescue Exception => e
    if model.__promiscuous_duplicate_key_exception?(e)
      options[:on_already_created] ||= proc { warn "ignoring already created record" }
      options[:on_already_created].call
    else
      raise e
    end
  end

  def update(should_create_on_failure=true)
    model.__promiscuous_fetch_existing(id).tap do |instance|
      # XXX With an ActiveRecord publisher, we may receive multiple operations,
      # and there is no way to figure out what version is what for now.
      options = {}
      if message_processor.operations.size == 1
        options[:version] = message.dependencies.first.try(:version)
      end

      instance.__promiscuous_update(self, options)
      instance.save!
    end
  rescue model.__promiscuous_missing_record_exception
    warn "upserting"
    create :on_already_created => proc { update(false) if should_create_on_failure }
  end

  def destroy
    if Promiscuous::Config.consistency == :eventual
      Promiscuous::Subscriber::Worker::EventualDestroyer.postpone_destroy(model, id)
    end

    model.__promiscuous_fetch_existing(id).tap do |instance|
      instance.destroy
    end
  rescue model.__promiscuous_missing_record_exception
    warn "ignoring missing record"
  end
end
